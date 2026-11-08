import FundScopeCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Zerodha", systemImage: "link") { ZerodhaSettings() }
            Tab("Data", systemImage: "externaldrive") { DataSettings() }
            Tab("Advanced", systemImage: "slider.horizontal.3") { AdvancedSettings() }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Data") {
                LabeledContent("Mode") {
                    Text(model.mode == .demo ? "Demo data" : "Your watchlist")
                }
                if model.mode == .demo {
                    Button("Exit Demo") { model.exitDemo() }
                }
                Button("Run Setup Again") { model.showOnboarding = true }
            }
            Section("Menu bar") {
                Toggle("Show FundScope in the menu bar", isOn: .constant(false)).disabled(true)
                Text("Available in Phase 8.").textStyle(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ZerodhaSettings: View {
    @Environment(AppModel.self) private var model
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var pasted = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { StatusDot(status: status) }
                if let date = model.kiteConnectedAt, model.kiteState == .connected {
                    LabeledContent("Connected", value: "\(FinanceFormat.date(date)), \(FinanceFormat.time(date))")
                }
                if let date = model.quotesFetchedAt {
                    LabeledContent("Last prices", value: "\(FinanceFormat.time(date)) · \(model.quotes.count) stocks")
                }
            } footer: {
                Text("Used only for live stock prices. FundScope never sees your Zerodha password, reads no account data and places no orders. Sessions end at 6 AM every day; reconnect each trading day.")
                    .textStyle(.caption)
            }

            Section("Your Kite Connect app") {
                if model.kiteAPIKey == nil {
                    TextField("API key", text: $apiKey)
                    SecureField("API secret", text: $apiSecret)
                    Button("Save to Keychain") { save() }
                        .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                } else {
                    LabeledContent("API key", value: "Saved in Keychain")
                    LabeledContent("API secret", value: "Saved in Keychain")
                    Button("Replace Key and Secret…") { replace() }
                }
                LabeledContent("Redirect URL") {
                    HStack {
                        Text(Kite.redirectURL).textStyle(.table).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Kite.redirectURL, forType: .string)
                        }
                    }
                }
            }

            Section {
                HStack {
                    switch model.kiteState {
                    case .connected:
                        Button("Refresh Prices") { Task { await model.refreshQuotes() } }
                        Button("Disconnect") { Task { await model.disconnectKite() } }
                    case .waitingForLogin:
                        ProgressView().controlSize(.small)
                        Text("Finish signing in on Zerodha's page in your browser…").textStyle(.secondary)
                    case .notConfigured:
                        Button("Connect") {}.disabled(true)
                    default:
                        Button(model.kiteState == .authRequired ? "Reconnect" : "Connect") { Task { await model.connectKite() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if model.kiteState == .waitingForLogin || pastedVisible {
                    HStack {
                        TextField("If the browser shows an error page, paste its address here", text: $pasted)
                        Button("Use") { usePasted() }.disabled(pasted.isEmpty)
                    }
                }
                if case .failed(let reason) = model.kiteState { Text(reason).textStyle(.caption, color: Palette.warning) }
                if let error = model.quoteError { Text(error).textStyle(.caption, color: Palette.warning) }
                if let message { Text(message).textStyle(.caption) }
            } footer: {
                Text("Setup: create an app at developers.kite.trade (Kite Connect plan, ₹500/month), set its Redirect URL to the address above, then paste the key and secret here.")
                    .textStyle(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var pastedVisible: Bool {
        if case .failed = model.kiteState { return true }
        return false
    }

    private var status: ProviderStatus {
        switch model.kiteState {
        case .connected: model.quoteError == nil ? .connected : .stale
        case .waitingForLogin: .updating
        case .failed: .unavailable
        default: .authRequired
        }
    }

    private func save() {
        do {
            try model.saveKiteCredentials(apiKey: apiKey, apiSecret: apiSecret)
            apiKey = ""
            apiSecret = ""
            message = "Saved. Now press Connect."
        } catch {
            message = error.localizedDescription
        }
    }

    private func replace() {
        Task { await model.forgetKiteCredentials() }
    }

    private func usePasted() {
        guard let url = URL(string: pasted.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        Task {
            do { try await model.completeKiteLogin(redirect: url); pasted = ""; message = "Connected." }
            catch { message = error.localizedDescription }
        }
    }
}

private struct DataSettings: View {
    var body: some View {
        Form {
            Section("Official NAV") {
                LabeledContent("Source", value: "AMFI")
                LabeledContent("Refresh", value: "Evenings on trading days (Phase 3)")
            }
            Section("Storage") {
                LabeledContent("Location", value: "~/Library/Application Support/FundScope")
                Text("Local storage arrives with portfolio import in Phase 2.").textStyle(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    var body: some View {
        Form {
            Section("Estimation model") {
                LabeledContent("Version", value: NAVEstimator.modelVersion)
                LabeledContent("Quote considered stale after", value: "5 minutes")
                LabeledContent("Not estimable below", value: "75% coverage")
            }
        }
        .formStyle(.grouped)
    }
}
