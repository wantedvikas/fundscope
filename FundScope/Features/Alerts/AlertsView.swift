import SwiftUI

/// Alert rules. Rules are kept in memory until Phase 8 adds storage and notifications.
struct AlertsView: View {
    struct Rule: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var detail: String
        var enabled: Bool
    }

    @State private var rules: [Rule] = [
        Rule(name: "Portfolio daily move", detail: "Estimated portfolio change beyond ±1.5%", enabled: true),
        Rule(name: "Estimate vs official gap", detail: "Official NAV differs from the final estimate by more than 0.5%", enabled: true),
        Rule(name: "Stale data", detail: "A data source has not updated for 2 trading days", enabled: true),
        Rule(name: "New disclosure", detail: "A newly imported disclosure changes more than 10% of a fund's holdings", enabled: false),
    ]

    var body: some View {
        Page {
            PageHeader(title: "Alerts", subtitle: "Rules that notify you about your portfolio") {
                Button("New Rule", systemImage: "plus") {}.disabled(true).help("Custom rules arrive in Phase 8")
            }
        } content: {
            InlineNotice(text: "Notifications are delivered from Phase 8. These rules show how monitoring will work; changes here are not saved yet.")
            PageSection(title: "Rules") {
                VStack(spacing: 0) {
                    ForEach($rules) { $rule in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).textStyle(.body)
                                Text(rule.detail).textStyle(.caption)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        .padding(.vertical, Space.s)
                        .padding(.horizontal, Space.m)
                        if rule.id != rules.last?.id { Divider() }
                    }
                }
                .hairlineBorder()
            }
            PageSection(title: "History") {
                Text("No alerts have fired.").textStyle(.secondary)
            }
        }
    }
}
