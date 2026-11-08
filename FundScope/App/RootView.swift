import FundScopeCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            NavigationStack(path: $model.path) {
                detail
                    .navigationDestination(for: FundRoute.self) { FundDetailView(route: $0) }
            }
        }
        .inspector(isPresented: $model.showInspector) {
            FundInspector()
                .inspectorColumnWidth(min: 260, ideal: Metrics.inspectorWidth, max: 380)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.mode == .demo { model.reload() } else { Task { await model.refreshAMFI() } }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh official NAVs from AMFI (⌘R)")
                .disabled(model.isRefreshingAMFI)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the inspector (⌥⌘I)")
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $model.showAddFunds) {
            AddFundsView { model.showAddFunds = false }
        }
        .sheet(isPresented: $model.showImportHoldings) {
            ImportHoldingsView { model.showImportHoldings = false }
        }
    }

    @ViewBuilder private var detail: some View {
        let section = model.selection ?? .watchlist
        if let storeError = model.storeError {
            ErrorState(title: "Local database unavailable", message: storeError, retryTitle: "Quit FundScope") { NSApplication.shared.terminate(nil) }
        } else if model.mode == .real, model.watched.isEmpty, ![.dataSources, .explorer, .alerts].contains(section) {
            EmptyState(symbol: "star",
                       title: "Your watchlist is empty",
                       message: "Add the funds you want to follow by name. FundScope never asks what you invested.",
                       actionTitle: "Add Funds") { model.showAddFunds = true }
        } else {
            switch section {
            case .watchlist: WatchlistView()
            case .liveNAV: LiveNAVView()
            case .nifty: NiftyView()
            case .explorer: FundExplorerView()
            case .compare: CompareFundsView()
            case .holdings: HoldingsAnalysisView()
            case .changes: PortfolioChangesView()
            case .accuracy: NAVAccuracyView()
            case .alerts: AlertsView()
            case .dataSources: DataSourcesView()
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(SidebarItem.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            }
            Section {
                Label(SidebarItem.dataSources.title, systemImage: SidebarItem.dataSources.symbol)
                    .tag(SidebarItem.dataSources)
            }
        }
        .listStyle(.sidebar)
    }
}
