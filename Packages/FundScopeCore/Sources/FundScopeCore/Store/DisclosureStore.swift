import Foundation

/// Imported AMC disclosures, one JSON file per fund per month: `Disclosures/<scheme code>/<yyyy-MM-dd>.json`.
/// Files are never overwritten: a published month doesn't change.
public enum DisclosureStore {
    public enum SaveResult: Equatable, Sendable { case saved, alreadyHave }

    static func folder(_ base: URL, code: String) -> URL {
        base.appending(path: "Disclosures", directoryHint: .isDirectory).appending(path: code, directoryHint: .isDirectory)
    }

    static func fileName(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: MarketCalendar.ist).year().month().day()) + ".json"
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ disclosure: Disclosure, in base: URL) throws -> SaveResult {
        let dir = folder(base, code: disclosure.fundCode)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: fileName(disclosure.disclosureDate))
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .alreadyHave }
        try encoder.encode(disclosure).write(to: url, options: .withoutOverwriting)
        return .saved
    }

    /// Disclosures per fund, oldest first. Unreadable files are skipped rather than failing the whole load.
    public static func load(codes: Set<String>, in base: URL) -> [String: [Disclosure]] {
        var result: [String: [Disclosure]] = [:]
        for code in codes {
            let dir = folder(base, code: code)
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let list = files.filter { $0.pathExtension == "json" }
                .compactMap { try? decoder.decode(Disclosure.self, from: Data(contentsOf: $0)) }
                .sorted { $0.disclosureDate < $1.disclosureDate }
            if !list.isEmpty { result[code] = list }
        }
        return result
    }

    /// A family build's starter file: the watchlist in order, plus the disclosures imported for it.
    struct Starter: Codable {
        var codes: [String]
        var disclosures: [Disclosure]
    }

    /// Saves a starter file's disclosures (months already saved are kept) and returns its watchlist codes.
    public static func seed(from url: URL, in base: URL) throws -> [String] {
        let starter = try decoder.decode(Starter.self, from: Data(contentsOf: url))
        for disclosure in starter.disclosures { _ = try save(disclosure, in: base) }
        return starter.codes
    }

    public static func delete(code: String, date: Date, in base: URL) throws {
        try FileManager.default.removeItem(at: folder(base, code: code).appending(path: fileName(date)))
    }
}
