import SwiftUI

/// Why a screen is empty, and the one thing to do about it.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(title).textStyle(.sectionTitle)
            Text(message).textStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, Space.xs)
            }
        }
        .padding(Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What failed and how to recover.
struct ErrorState: View {
    let title: String
    let message: String
    var retryTitle = "Retry"
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.warning)
            Text(title).textStyle(.sectionTitle)
            Text(message).textStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let retry { Button(retryTitle, action: retry).padding(.top, Space.xs) }
        }
        .padding(Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingState: View {
    var label = "Loading…"

    var body: some View {
        HStack(spacing: Space.xs) {
            ProgressView().controlSize(.small)
            Text(label).textStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline notice for warnings that belong to a section (stale data, low coverage).
struct InlineNotice: View {
    enum Tone { case info, warning }
    let text: String
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: tone == .warning ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(tone == .warning ? Palette.warning : Palette.textSecondary)
            // No fixedSize: at the near-zero width macOS uses to compute the window's minimum size, a vertically
            // fixed text becomes one word per line and stretches the whole window's content (Live NAV broke this way).
            Text(text).textStyle(.secondary)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tone == .warning ? Palette.warning : Palette.fill).opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.medium))
    }
}
