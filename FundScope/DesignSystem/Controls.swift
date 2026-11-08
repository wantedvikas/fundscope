import FundScopeCore
import SwiftUI
import UniformTypeIdentifiers

enum TimeRange: String, CaseIterable, Identifiable {
    case m1 = "1M", m3 = "3M", m6 = "6M", y1 = "1Y", y3 = "3Y", y5 = "5Y", all = "All"
    var id: String { rawValue }

    func start(from end: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        switch self {
        case .m1: return cal.date(byAdding: .month, value: -1, to: end)!
        case .m3: return cal.date(byAdding: .month, value: -3, to: end)!
        case .m6: return cal.date(byAdding: .month, value: -6, to: end)!
        case .y1: return cal.date(byAdding: .year, value: -1, to: end)!
        case .y3: return cal.date(byAdding: .year, value: -3, to: end)!
        case .y5: return cal.date(byAdding: .year, value: -5, to: end)!
        case .all: return .distantPast
        }
    }
}

struct RangePicker: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(options) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Single fund picker (menu).
struct FundPicker: View {
    let funds: [FundInfo]
    @Binding var selection: String

    var body: some View {
        Picker("Fund", selection: $selection) {
            ForEach(funds) { Text($0.name).tag($0.code) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Multi-fund picker in a popover with search.
struct FundMultiPicker: View {
    let funds: [FundInfo]
    @Binding var selection: Set<String>
    var limit = 5
    @State private var isPresented = false
    @State private var query = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("\(selection.count) funds", systemImage: "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.xs) {
                TextField("Search funds", text: $query).textFieldStyle(.roundedBorder)
                List(funds.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { fund in
                    Toggle(isOn: Binding(
                        get: { selection.contains(fund.code) },
                        set: { on in
                            if on, selection.count < limit { selection.insert(fund.code) }
                            else if !on { selection.remove(fund.code) }
                        })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fund.name).textStyle(.body)
                            Text("\(fund.amc) · \(fund.category)").textStyle(.caption)
                        }
                    }
                    .disabled(!selection.contains(fund.code) && selection.count >= limit)
                }
                .listStyle(.plain)
                .frame(height: 240)
                Text("Up to \(limit) funds").textStyle(.caption)
            }
            .padding(Space.s)
            .frame(width: 340)
        }
    }
}

/// Tooltip for chart hover.
struct ChartTooltip: View {
    let title: String
    let rows: [(label: String, value: String, color: Color?)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).textStyle(.label)
            ForEach(rows, id: \.label) { row in
                HStack(spacing: Space.xs) {
                    if let color = row.color { Circle().fill(color).frame(width: 6, height: 6) }
                    Text(row.label).textStyle(.caption)
                    Spacer(minLength: Space.s)
                    Text(row.value).textStyle(.table)
                }
            }
        }
        .padding(Space.xs)
        .frame(minWidth: 160)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.small))
        .hairlineBorder(radius: Radius.small)
    }
}

/// Drop area for import files. Calls `onDrop` with file URLs; validation happens in the importer.
struct ImportDropZone: View {
    let title: String
    let message: String
    var isEnabled = true
    var allowedTypes: [UTType] = [.commaSeparatedText, .spreadsheet]
    let onFiles: ([URL]) -> Void
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isTargeted ? Palette.accent : Palette.textTertiary)
            Text(title).textStyle(.sectionTitle)
            Text(message).textStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose File…") { showImporter = true }
                .disabled(!isEnabled)
                .padding(.top, Space.xxs)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
        .background(isTargeted ? Palette.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .strokeBorder(isTargeted ? Palette.accent : Palette.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .opacity(isEnabled ? 1 : 0.6)
        .dropDestination(for: URL.self) { urls, _ in
            guard isEnabled else { return false }
            onFiles(urls)
            return true
        } isTargeted: { isTargeted = $0 && isEnabled }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { onFiles(urls) }
        }
    }
}
