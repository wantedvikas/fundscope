import FundScopeCore
import SwiftUI

/// Right-hand inspector: details of the selected fund in the current portfolio.
struct FundInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let code = model.inspectedFund, let data = model.data, let fund = model.fund(code) {
            let watched = model.watched.first { $0.fund.code == code }
            let estimate = Analytics.estimate(data, fund: fund)
            let disclosure = Analytics.latestDisclosure(data, fund: code)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(fund.name).textStyle(.sectionTitle)
                        Text("\(fund.amc) · \(fund.category) · \(fund.plan.rawValue.capitalized)").textStyle(.caption)
                    }

                    InspectorSection(title: "NAV") {
                        InspectorRow(label: "Official") { ValueText(value: estimate?.baselineNAV, kind: .nav) }
                        InspectorRow(label: "Estimated") {
                            ValueText(value: estimate?.estimatedNAV, kind: .nav, missingReason: notEstimableReason(estimate))
                        }
                        InspectorRow(label: "Est. change") {
                            ValueText(value: estimate?.estimatedReturn, kind: .percent, colored: true, missingReason: notEstimableReason(estimate))
                        }
                        if let estimate { CoverageMeter(estimate: estimate, showLegend: false).padding(.top, Space.xxs) }
                    }

                    if let watched {
                        InspectorSection(title: "Official NAV") {
                            InspectorRow(label: "Date") { Text(watched.official.map { FinanceFormat.date($0.date) } ?? "—").textStyle(.table) }
                            InspectorRow(label: "1-day change") {
                                ValueText(value: watched.officialChange, kind: .percent, colored: true, missingReason: "Needs two days of official NAVs")
                            }
                        }
                    }

                    if let disclosure {
                        InspectorSection(title: "Top holdings · \(FinanceFormat.date(disclosure.disclosureDate))") {
                            ForEach(disclosure.holdings.prefix(8)) { h in
                                InspectorRow(label: h.security?.name ?? h.rawName) { ValueText(value: h.weight, kind: .percent) }
                            }
                        }
                    }

                    Button("Open Fund") { model.open(code) }
                }
                .padding(Space.m)
            }
        } else {
            EmptyState(symbol: "sidebar.right", title: "Nothing selected", message: "Select a fund in any table to see its details here.")
        }
    }

    private func notEstimableReason(_ e: NAVEstimator.Estimate?) -> String {
        if case .notEstimable(let reason) = e?.status { return reason }
        return "Not available"
    }
}
