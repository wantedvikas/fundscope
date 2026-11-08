import SwiftUI

/// First-run setup: add funds by name, or look around with demo data.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.welcome

    enum Step { case welcome, setup, adding }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome: welcome
            case .setup: setup
            case .adding: AddFundsView { close() }
            }
        }
        .frame(width: step == .adding ? 820 : 640, height: step == .adding ? 600 : 460)
        .background(Palette.background)
    }

    private func close() {
        model.finishOnboarding()
        dismiss()
    }

    private var welcome: some View {
        VStack(spacing: Space.m) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("Your mutual funds, beyond the NAV.")
                .font(.system(size: 26, weight: .semibold))
            Text("Follow your funds, understand the companies behind them, and see how they're likely moving during the market day.")
                .textStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Get started") { withAnimation(.snappy) { step = .setup } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, Space.s)
            Spacer()
            Text("No account, no amounts. FundScope only needs the names of your funds.")
                .textStyle(.caption)
        }
        .padding(Space.xxxl)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Build your watchlist").textStyle(.screenTitle)
                Text("Tell FundScope which funds to follow. It looks them up in AMFI's official scheme list.").textStyle(.secondary)
            }
            HStack(alignment: .top, spacing: Space.m) {
                SetupOption(
                    title: "Add your funds",
                    badge: "Recommended",
                    message: "Search by name, paste a list, or pick a holdings file. Only fund names are read, never amounts.",
                    buttonTitle: "Add funds") { step = .adding }
                SetupOption(
                    title: "Explore with demo data",
                    badge: nil,
                    message: "Fictional funds and prices that show every screen, including live estimates.",
                    buttonTitle: "Open demo") {
                    model.enterDemo()
                    dismiss()
                }
            }
            Spacer()
            HStack {
                Button("Not now") { close() }
                Spacer()
            }
        }
        .padding(Space.xxl)
    }
}

private struct SetupOption: View {
    let title: String
    let badge: String?
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Badge row keeps a fixed height so both cards line up.
            Group {
                if let badge { Pill(text: badge, tint: Palette.accent) } else { Pill(text: " ").hidden() }
            }
            Text(title).textStyle(.sectionTitle)
            Text(message).textStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(buttonTitle, action: action)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .hairlineBorder(radius: Radius.large)
    }
}
