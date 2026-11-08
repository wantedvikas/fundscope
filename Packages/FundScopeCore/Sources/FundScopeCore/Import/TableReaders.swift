import Foundation
import ZIPFoundation

/// A sheet of raw cell strings, exactly as read from the file.
public struct RawSheet: Hashable, Sendable {
    public let name: String
    public let rows: [[String]]

    public init(name: String, rows: [[String]]) {
        self.name = name
        self.rows = rows
    }
}

public enum TableReadError: Error, Equatable, LocalizedError {
    case unsupportedFile(String)
    case tooLarge
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let ext) where ext.lowercased() == "xls": "This is an old-format Excel file. Open it in Excel or Numbers, save as .xlsx, and import that."
        case .unsupportedFile(let ext): "“.\(ext)” files can't be imported. Use a CSV or XLSX export."
        case .tooLarge: "The file is larger than 50 MB."
        case .unreadable(let reason): "The file couldn't be read: \(reason)"
        }
    }
}

public enum TableReader {
    static let maxBytes = 50 * 1024 * 1024

    /// Reads a CSV or XLSX file into sheets of strings. Formulas are never evaluated.
    public static func read(_ url: URL) throws -> [RawSheet] {
        let ext = url.pathExtension.lowercased()
        guard ["csv", "txt", "xlsx", "xls"].contains(ext) else { throw TableReadError.unsupportedFile(url.pathExtension) }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else { throw TableReadError.tooLarge }
        // Some AMCs name modern workbooks ".xls" (Nippon); the zip signature tells them apart from old binary Excel.
        if data.starts(with: [0x50, 0x4B]) { return try XLSXReader.read(data) }
        if ext == "xls" || ext == "xlsx" { throw TableReadError.unsupportedFile(ext == "xls" ? "xls" : "xlsx") }
        return [RawSheet(name: url.deletingPathExtension().lastPathComponent, rows: CSVReader.parse(data))]
    }
}

/// RFC 4180 CSV: quoted fields, escaped quotes, commas and newlines inside quotes, CRLF, BOM.
public enum CSVReader {
    public static func parse(_ data: Data) -> [[String]] {
        let text = String(decoding: data, as: UTF8.self)
        return parse(text)
    }

    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        let delimiter: Unicode.Scalar = detectDelimiter(chars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.unicodeScalars.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.unicodeScalars.append(c)
            }
            i += 1
        }
        row.append(field)
        if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows
    }

    /// Comma unless the first line has more semicolons or tabs.
    static func detectDelimiter(_ chars: [Unicode.Scalar]) -> Unicode.Scalar {
        let firstLine = chars.prefix { $0 != "\n" && $0 != "\r" }
        let counts: [(Unicode.Scalar, Int)] = [",", ";", "\t"].map { d in (d, firstLine.filter { $0 == d }.count) }
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? ","
    }
}

/// Minimal XLSX reader: shared strings, inline strings and cell values. No formulas, styles or macros.
public enum XLSXReader {
    public static func read(_ data: Data) throws -> [RawSheet] {
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) } catch { throw TableReadError.unreadable("not a valid XLSX file") }

        func entry(_ path: String) throws -> Data? {
            guard let e = archive[path] else { return nil }
            var out = Data()
            _ = try archive.extract(e, skipCRC32: false) { out.append($0) }
            return out
        }

        guard let workbook = try entry("xl/workbook.xml") else { throw TableReadError.unreadable("workbook is missing") }
        let rels = try entry("xl/_rels/workbook.xml.rels").map(XMLRows.relationships) ?? [:]
        let shared = try entry("xl/sharedStrings.xml").map(XMLRows.sharedStrings) ?? []

        return try XMLRows.sheets(workbook).compactMap { name, relID in
            guard var target = rels[relID] else { return nil }
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            guard let xml = try entry(target) else { return nil }
            return RawSheet(name: name, rows: XMLRows.cells(xml, shared: shared))
        }
    }
}

/// XMLParser-based helpers for the few XLSX parts we read.
private final class XMLRows: NSObject, XMLParserDelegate {
    private var onStart: (String, [String: String]) -> Void = { _, _ in }
    private var onEnd: (String, String) -> Void = { _, _ in }
    private var text = ""

    private static func parse(_ data: Data, start: @escaping (String, [String: String]) -> Void, end: @escaping (String, String) -> Void) {
        let delegate = XMLRows()
        delegate.onStart = start
        delegate.onEnd = end
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        onStart(name, attributes)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        onEnd(name, text)
    }

    static func relationships(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        parse(data, start: { name, a in
            if name == "Relationship", let id = a["Id"], let target = a["Target"] { result[id] = target }
        }, end: { _, _ in })
        return result
    }

    static func sheets(_ data: Data) -> [(String, String)] {
        var result: [(String, String)] = []
        parse(data, start: { name, a in
            if name == "sheet", let n = a["name"], let id = a["r:id"] { result.append((n, id)) }
        }, end: { _, _ in })
        return result
    }

    static func sharedStrings(_ data: Data) -> [String] {
        var result: [String] = []
        var current = ""
        parse(data, start: { name, _ in if name == "si" { current = "" } },
              end: { name, text in
                  if name == "t" { current += text }
                  if name == "si" { result.append(current) }
              })
        return result
    }

    static func cells(_ data: Data, shared: [String]) -> [[String]] {
        var rows: [[String]] = []
        var row: [Int: String] = [:]
        var cellRef = "", cellType = "", value = ""
        parse(data, start: { name, a in
            switch name {
            case "row": row = [:]
            case "c": cellRef = a["r"] ?? ""; cellType = a["t"] ?? ""; value = ""
            default: break
            }
        }, end: { name, text in
            switch name {
            case "v", "t": value += text
            case "c":
                let resolved = cellType == "s" ? (Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : value
                row[columnIndex(cellRef) ?? row.count] = resolved
            case "row":
                guard let maxCol = row.keys.max() else { return }
                let cells = (0...maxCol).map { row[$0] ?? "" }
                if !cells.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(cells) }
            default: break
            }
        })
        return rows
    }

    /// "C12" → 2
    static func columnIndex(_ ref: String) -> Int? {
        let letters = ref.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return nil }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value - 64) } - 1
    }
}
