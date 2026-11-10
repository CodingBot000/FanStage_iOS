import XCTest

final class FanStageUITests: XCTestCase {
    func testTabsCommunityAndMessageFlow() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Find your moment"].waitForExistence(timeout: 10))
        app.staticTexts["Studio session"].tap()
        XCTAssertTrue(app.navigationBars["LIVE"].waitForExistence(timeout: 5))
        let chatField = app.textFields["Message"]
        XCTAssertTrue(chatField.waitForExistence(timeout: 5))
        chatField.tap(); chatField.typeText("Hello live")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["Hello live"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Back"].tap()
        app.tabBars.buttons["Community"].tap()
        XCTAssertTrue(app.navigationBars["Community"].waitForExistence(timeout: 5))
        app.buttons["Paper Lantern"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Paper Lantern"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Media"].tap()
        XCTAssertTrue(app.staticTexts["Videos & moments"].waitForExistence(timeout: 5))
        app.buttons["Replay"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Watch replay"].exists)
        app.tabBars.buttons["Messages"].tap()
        app.cells.firstMatch.tap()
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Hello FanStage")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["Hello FanStage"].waitForExistence(timeout: 5))
    }
    func testServerDraftRemainsBeforeConnection() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Studio session"].waitForExistence(timeout: 10))
        app.staticTexts["Studio session"].tap()
        app.buttons["Chat settings"].tap()
        let toggle = app.switches["Local server"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("unsent draft")
        let send = app.buttons["live_chat_send"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertEqual(field.value as? String, "unsent draft")
    }
}
