//
//  OpenPaneUITests.swift
//  OpenPaneUITests
//
//  Created by Christopher Rego on 6/4/26.
//

import XCTest

final class OpenPaneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    @MainActor
    func testLaunchShowsDualPaneShell() throws {
        assertDualPaneShellVisible()

        XCTAssertTrue(app.buttons["New Folder"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Copy to Other Pane"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Back"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Forward"].firstMatch.exists)
    }

    @MainActor
    func testActivePaneCanSwitchToRightPane() throws {
        assertDualPaneShellVisible()

        element("right-file-pane").click()

        XCTAssertTrue(app.staticTexts["Right pane active"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPaneStructureSurvivesDividerDrag() throws {
        assertDualPaneShellVisible()

        let divider = element("pane-split-divider")
        if divider.waitForExistence(timeout: 2) {
            let leftPane = element("left-file-pane")
            let dividerCenter = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let narrowLeftTarget = leftPane.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            dividerCenter.press(forDuration: 0.1, thenDragTo: narrowLeftTarget)
        }

        assertDualPaneShellVisible()
    }

    private func assertDualPaneShellVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element("main-content-surface").waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element("left-file-pane").exists, file: file, line: line)
        XCTAssertTrue(element("right-file-pane").exists, file: file, line: line)
        XCTAssertTrue(element("left-file-list").exists, file: file, line: line)
        XCTAssertTrue(element("right-file-list").exists, file: file, line: line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
