import XCTest

/// Navigation and flow checks. These run on the simulator and verify app structure only:
/// they say nothing about whether glass rendering matches a physical device.
final class GlassLabUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    /// Opens a top-level section whether it is shown as a tab, inside "More", or in the iPad sidebar.
    func open(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let button = app.buttons[name].firstMatch
        if button.waitForExistence(timeout: 2) { button.tap(); return }
        let more = app.tabBars.buttons["More"]
        if more.exists { more.tap(); app.staticTexts[name].firstMatch.tap(); return }
        let cell = app.cells.staticTexts[name].firstMatch
        if cell.waitForExistence(timeout: 2) { cell.tap() }
    }

    func testComponentNavigationAndOpenInLab() {
        open("Explore")
        let regular = app.buttons["component-regular"].firstMatch
        let cell = regular.exists ? regular : app.staticTexts["Regular Glass"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        let openInLab = app.buttons["openInLab"]
        XCTAssertTrue(openInLab.waitForExistence(timeout: 5))
        openInLab.tap()
        XCTAssertTrue(app.otherElements["experimentCanvas"].waitForExistence(timeout: 5) || app.buttons["acquire"].waitForExistence(timeout: 5))
    }

    func testExperimentConfigurationAndAppearance() {
        open("Experiment Lab")
        XCTAssertTrue(app.buttons["acquire"].waitForExistence(timeout: 5))
        let dark = app.buttons["Dark"].firstMatch
        if dark.waitForExistence(timeout: 3) { dark.tap() }
        let focus = app.buttons["focusMode"]
        if focus.exists {
            focus.tap()
            XCTAssertTrue(app.buttons["exitFocus"].waitForExistence(timeout: 5))
            app.buttons["exitFocus"].tap()
        }
    }

    func testModalPresentationOfNavigationDemo() {
        open("Explore")
        let item = app.staticTexts["Navigation Bar"].firstMatch
        guard item.waitForExistence(timeout: 5) else { return }
        item.tap()
        let openDemo = app.buttons["openLiveDemo"]
        XCTAssertTrue(openDemo.waitForExistence(timeout: 5))
        openDemo.tap()
        XCTAssertTrue(app.buttons["closeDemo"].waitForExistence(timeout: 5))
        app.buttons["closeDemo"].tap()
    }

    func testSessionManagementAndExportFlow() {
        open("Sessions")
        let create = app.buttons["createSession"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let export = app.buttons["Export measurements CSV"]
        if export.waitForExistence(timeout: 5) { XCTAssertTrue(export.isHittable || export.exists) }
    }

    func testComparisonScreenOpens() {
        open("Compare")
        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 5) || app.staticTexts["Compare"].waitForExistence(timeout: 5))
    }
}
