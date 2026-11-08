import FundScopeCore
import SwiftUI

struct DataSourcesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sources = model.data?.dataSources ?? Self.unconfigured
        Page {
            PageHeader(title: "Data Sources", subtitle: "Where FundScope's numbers come from") {
                Button("Retry", systemImage: "arrow.clockwise") {
                    if model.mode == .demo { model.reload() } else { Task { await model.refreshAMFI() } }
                }
                .disabled(model.isRefreshingAMFI)
            }
        } content: {
            VStack(spacing: 0) {
                ForEach(sources) { source in
                    ConnectionRow(source: source)
                    if source.id != sources.last?.id { Divider() }
                }
            }
            .hairlineBorder()
            PageSection(title: "Sync log") {
                Text(model.data?.isDemo == true ? "Demo data is generated locally; no sync has run." : model.amfiFetchedAt.map { "AMFI NAV file downloaded \(FinanceFormat.date($0)), \(FinanceFormat.time($0))." } ?? "AMFI hasn't been reached yet.")
                    .textStyle(.secondary)
            }
        }
    }

    static let unconfigured: [DataSourceHealth] = [
        .init(name: "AMFI", detail: "Scheme list and official NAV", status: .unavailable, lastSuccess: nil, latestDataDate: nil, records: nil, warning: nil),
    ]
}

/// One provider's health row.
struct ConnectionRow: View {
    let source: DataSourceHealth

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(source.name).textStyle(.body).fontWeight(.medium)
                Text(source.detail).textStyle(.caption)
                if let warning = source.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .textStyle(.caption, color: Palette.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusDot(status: source.status).frame(width: 170, alignment: .leading)
            fact("Last update", source.lastSuccess.map { "\(FinanceFormat.shortDate($0)), \(FinanceFormat.time($0))" })
            fact("Data as of", source.latestDataDate.map(FinanceFormat.date))
            fact("Records", source.records.map { "\($0)" })
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    private func fact(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textStyle(.cardTitle)
            if let value { Text(value).textStyle(.table) } else { MissingValue(reason: "Never updated").textStyle(.table) }
        }
        .frame(width: 110, alignment: .leading)
    }
}
