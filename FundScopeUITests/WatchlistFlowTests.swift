import XCTest

/// Adds funds by name into a fresh in-memory store, using a saved AMFI file (no network).
final class WatchlistFlowTests: XCTestCase {
    static let names = [
        "Quant Small Cap Fund", "Parag Parikh Flexi Cap Fund", "Axis Large Cap Fund", "HDFC Mid Cap Fund",
        "SBI Small Cap Fund", "WOC Mid Cap Fund", "UTI Nifty 50 Index Fund", "ICICI Pru Large & Mid Cap Fund",
        "Mirae Asset Large Cap Fund", "Invesco India Arbitrage Fund",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testAddFundNamesFromOnboarding() throws {
        let app = try launch(extra: ["-prefillFundNames", Self.names.joined(separator: "|")])
        app.buttons["Get started"].click()
        app.buttons["Add funds"].click()
        XCTAssertTrue(app.buttons["Find Funds"].waitForExistence(timeout: 5))
        app.buttons["Find Funds"].click()
        XCTAssertTrue(app.buttons["Add 10 Funds"].waitForExistence(timeout: 5), "Every name should match one scheme")
        attach(app, "AddFunds-matches")
        app.buttons["Add 10 Funds"].click()
        app.buttons["Done"].click()
        XCTAssertTrue(app.staticTexts["Parag Parikh Flexi Cap Fund"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WhiteOak Capital Mid Cap Fund"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Demo data"].exists, "Real watchlist must not show the demo badge")
        attach(app, "Watchlist-real")
        app.outlines.staticTexts["Fund Explorer"].click()
        XCTAssertTrue(app.staticTexts["Watching"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "Explorer-real")
    }

    /// With 10 funds, Live NAV must keep its title and column headers visible (they used to slide under the toolbar).
    @MainActor func testLiveNAVWithManyFundsKeepsHeaderVisible() throws {
        let app = try launch(extra: ["-prefillFundNames", Self.names.joined(separator: "|")])
        app.buttons["Get started"].click()
        app.buttons["Add funds"].click()
        app.buttons["Find Funds"].click()
        app.buttons["Add 10 Funds"].click()
        app.buttons["Done"].click()
        app.outlines.staticTexts["Live NAV"].click()
        XCTAssertTrue(app.buttons["Official NAV"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["Official NAV"].firstMatch.exists)
        let header = app.buttons["Official NAV"].firstMatch.exists ? app.buttons["Official NAV"].firstMatch : app.staticTexts["Official NAV"].firstMatch
        let toolbarBottom = app.toolbars.firstMatch.frame.maxY
        XCTAssertGreaterThanOrEqual(header.frame.minY, toolbarBottom, "Column headers are hidden under the toolbar")
        attach(app, "LiveNAV-10-funds")
    }

    @MainActor func testImportFundHoldings() throws {
        let files = try ["ppfas_ppfcf_2026-08.xlsx", "ppfas_ppfcf_2026-09.xlsx"].map(copyToContainer)
        let app = try launch(extra: ["-prefillFundNames", "Parag Parikh Flexi Cap Fund|HDFC Mid Cap Fund",
                                     "-importHoldingsFixture", files.joined(separator: "|")])
        app.buttons["Get started"].click()
        app.buttons["Add funds"].click()
        app.buttons["Find Funds"].click()
        app.buttons["Add 2 Funds"].click()
        app.buttons["Done"].click()
        app.buttons["Import Holdings"].firstMatch.click()
        // Both months are read and matched to Parag Parikh Flexi Cap automatically.
        XCTAssertTrue(app.buttons["Import 2 Portfolios"].waitForExistence(timeout: 10))
        attach(app, "ImportHoldings-review")
        app.buttons["Import 2 Portfolios"].click()
        XCTAssertTrue(app.staticTexts["Imported 2 monthly portfolios."].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        app.outlines.staticTexts["Holdings Analysis"].click()
        XCTAssertTrue(app.staticTexts["HDFC Bank Limited"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "HoldingsAnalysis-real")
        app.outlines.staticTexts["Holdings Changes"].click()
        XCTAssertTrue(app.staticTexts["New holdings"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["Exited"].firstMatch.exists)
        attach(app, "HoldingsChanges-real")
    }

    @MainActor private func copyToContainer(_ name: String) throws -> String {
        let (base, ext) = (String(name.split(separator: ".")[0]), String(name.split(separator: ".")[1]))
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: base, withExtension: ext))
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.vikasghodke.FundScope/Data/tmp/uitest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appending(path: name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        return target.path
    }

    /// Copies the AMFI fixture into the sandboxed app's container, where the app may read it.
    @MainActor private func launch(onboarded: Bool = false, extra: [String] = []) throws -> XCUIApplication {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "amfi_navall_subset", withExtension: "txt"))
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.vikasghodke.FundScope/Data/tmp/uitest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appending(path: "amfi.txt")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-dataMode", "real", "-storeInMemory", "YES", "-amfiFixture", target.path,
                               "-onboarded", onboarded ? "YES" : "NO", "-appearance", "light"] + extra
        app.launch()
        if !onboarded { XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10)) }
        return app
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
