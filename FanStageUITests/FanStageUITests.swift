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
    func testPendingRecoveryAndDiscardUIWithServer() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["FANSTAGE_TEST_ACK_PROXY"], let token = env["FANSTAGE_TEST_TOKEN"] else { throw XCTSkip("Isolated chat fixture not configured") }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["FANSTAGE_UI_TEST_URL"] = url
        app.launchEnvironment["FANSTAGE_UI_TEST_TOKEN"] = token
        app.launch()
        XCTAssertTrue(app.staticTexts["Studio session"].waitForExistence(timeout: 10))
        app.staticTexts["Studio session"].tap()
        app.buttons["Chat settings"].tap()
        let toggle = app.switches["Local server"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10))
        app.buttons["Chat settings"].tap()
        let field = app.textFields["Message"]
        field.tap(); field.typeText("pending retry")
        app.buttons["live_chat_send"].tap()
        let pending = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'pending_'")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        let originalID = pending.identifier
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Discard pending message?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(pending.identifier, originalID)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["pending retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(pending.exists)
        field.tap(); field.typeText("pending discard")
        app.buttons["live_chat_send"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        app.alerts.buttons["Discard"].tap()
        XCTAssertFalse(app.buttons["Delete"].exists)
        field.tap(); field.typeText("pending reconnect")
        app.buttons["live_chat_send"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        let reconnectID = pending.identifier
        app.buttons["Chat settings"].tap()
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
        XCTAssertFalse(app.switches["Local server"].exists)
        XCTAssertEqual(pending.identifier, reconnectID)
        app.navigationBars.buttons["Back"].tap()
        let leaveAlert = app.alerts["Pending messages"]
        XCTAssertTrue(leaveAlert.waitForExistence(timeout: 5))
        leaveAlert.buttons["Stay"].tap()
        XCTAssertEqual(pending.identifier, reconnectID)
        app.navigationBars.buttons["Back"].tap()
        app.alerts["Pending messages"].buttons["Leave"].tap()
        app.staticTexts["Studio session"].tap()
        XCTAssertTrue(app.staticTexts["pending reconnect"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Delete"].exists)
    }
}
