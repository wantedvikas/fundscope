import SwiftUI

@main
struct FundScopeApp: App {
    @State private var model = AppModel()
    /// "system", "light" or "dark". `-appearance dark` as a launch argument overrides it (UI tests).
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("FundScope", id: "main") {
            RootView()
                .environment(model)
                .environment(\.isDemoData, model.mode == .demo)
                .frame(minWidth: Metrics.windowMinWidth, minHeight: Metrics.windowMinHeight)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        CommandMenu("Go") {
            ForEach(Array(SidebarItem.allCases.prefix(9).enumerated()), id: \.element) { index, item in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button(SidebarItem.dataSources.title) { model.selection = .dataSources }
        }
        CommandGroup(after: .newItem) {
            Button("Add Funds…") { model.showAddFunds = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.container == nil)
            Button("Import Fund Holdings…") { model.showImportHoldings = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.mode != .real)
            Button("Refresh NAVs") {
                if model.mode == .demo { model.reload() } else { Task { await model.refreshAMFI() } }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
