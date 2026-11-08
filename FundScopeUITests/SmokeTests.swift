import XCTest

/// Launches the app in demo mode and visits every sidebar section in light and dark mode.
/// Screenshots are kept in the test result for visual review.
final class SmokeTests: XCTestCase {
    static let sections = [
        "Watchlist", "Live NAV", "Nifty 50", "Fund Explorer", "Compare Funds",
        "Holdings Analysis", "Holdings Changes", "NAV Accuracy", "Alerts", "Data Sources",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testEverySectionInLightMode() { visitAll(style: "Light") }
    @MainActor func testEverySectionInDarkMode() { visitAll(style: "Dark") }

    @MainActor func testFirstLaunchShowsOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-dataMode", "real", "-storeInMemory", "YES", "-onboarded", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your mutual funds, beyond the NAV."].waitForExistence(timeout: 10))
        attach(app, "Onboarding-welcome")
        app.buttons["Get started"].click()
        XCTAssertTrue(app.staticTexts["Build your watchlist"].waitForExistence(timeout: 5))
        attach(app, "Onboarding-setup")
    }

    @MainActor func testOpenFundDetail() {
        let app = launchDemo(style: "Light")
        app.outlines.staticTexts["Live NAV"].click()
        let row = app.staticTexts["Sahyadri Large Cap Fund"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()
        XCTAssertTrue(app.staticTexts["Intraday estimate"].waitForExistence(timeout: 5))
        attach(app, "FundDetail-today")
    }

    @MainActor private func launchDemo(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-dataMode", "demo", "-onboarded", "YES", "-appearance", style.lowercased()]
        app.launch()
        XCTAssertTrue(app.outlines.staticTexts["Watchlist"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func visitAll(style: String) {
        let app = launchDemo(style: style)
        for section in Self.sections {
            app.outlines.staticTexts[section].click()
            XCTAssertTrue(app.staticTexts["Demo data"].firstMatch.waitForExistence(timeout: 5), "\(section) has no demo badge")
            attach(app, "\(style)-\(section)")
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
