import FundScopeCore
import SwiftUI

extension EnvironmentValues {
    /// True when the window shows demo data; page headers show the Demo badge.
    @Entry var isDemoData = false
}

/// Title row of every screen: title, subtitle facts, trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.isDemoData) private var isDemo

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.xs) {
                    Text(title).textStyle(.screenTitle)
                    if isDemo { DemoBadge() }
                }
                if let subtitle { Text(subtitle).textStyle(.secondary) }
            }
            Spacer(minLength: Space.m)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Standard scrolling page: header, then sections separated by consistent spacing.
struct Page<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                content
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
    }
}

/// A titled section. No card chrome: hierarchy comes from type and space.
struct PageSection<Accessory: View, Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).textStyle(.sectionTitle)
                if let caption { Text(caption).textStyle(.caption) }
                Spacer()
                accessory
            }
            content
        }
    }
}

extension PageSection where Accessory == EmptyView {
    init(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, caption: caption, accessory: { EmptyView() }, content: content)
    }
}

/// Fixed-height container for a `Table` placed inside a scrolling page.
struct TableFrame<Content: View>: View {
    let rows: Int
    var maxRows = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(height: CGFloat(min(max(rows, 1), maxRows) + 1) * (Metrics.tableRow + 6) + Space.m)
            .hairlineBorder()
    }
}

/// Inspector building blocks.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).textStyle(.cardTitle)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.secondary)
            Spacer(minLength: Space.xs)
            value
        }
    }
}
