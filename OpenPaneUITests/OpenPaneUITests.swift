//
//  OpenPaneUITests.swift
//  OpenPaneUITests
//
//  Created by Christopher Rego on 6/4/26.
//

import XCTest

final class OpenPaneUITests: XCTestCase {
    private var app: XCUIApplication!
    private var driver: OpenPaneUITestDriver!

    override func setUpWithError() throws {
        continueAfterFailure = false

        driver = OpenPaneUITestDriver(testCase: self)
        app = try driver.launchApp()
    }

    override func tearDownWithError() throws {
        driver?.cleanup()
        driver = nil
        app = nil
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

        driver.runToolsMenuCommand("Switch Active Pane", in: app)

        XCTAssertTrue(app.staticTexts["Right pane active"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPaneStructureSurvivesDividerDrag() throws {
        assertDualPaneShellVisible()

        dragDivider(toPane: "left-file-pane", normalizedX: 0.2)
        assertDualPaneShellVisible()

        dragDivider(toPane: "right-file-pane", normalizedX: 0.8)
        assertDualPaneShellVisible()
    }

    @MainActor
    func testAppCanReactivateAfterSwitchingAway() throws {
        assertDualPaneShellVisible()

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        app.activate()

        assertDualPaneShellVisible()
    }

    private func dragDivider(
        toPane paneIdentifier: String,
        normalizedX: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let divider = element("pane-split-divider")
        XCTAssertTrue(divider.waitForExistence(timeout: 2), file: file, line: line)
        let targetPane = element(paneIdentifier)
        let dividerCenter = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragTarget = targetPane.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5))
        dividerCenter.press(forDuration: 0.1, thenDragTo: dragTarget)
    }

    private func assertDualPaneShellVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        driver.assertDualPaneShellVisible(in: app, file: file, line: line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        driver.element(identifier, in: app)
    }
}

final class OpenPaneUITestDriver {
    private let testCase: XCTestCase
    private let fileManager: FileManager
    private var interruptionMonitor: NSObjectProtocol?
    private var fixtureRootURL: URL?

    init(testCase: XCTestCase, fileManager: FileManager = .default) {
        self.testCase = testCase
        self.fileManager = fileManager
    }

    func launchApp() throws -> XCUIApplication {
        let fixtureRootURL = try makeFixtureRoot()
        self.fixtureRootURL = fixtureRootURL

        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["OPENPANE_UI_TEST_ROOT"] = fixtureRootURL.path
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"

        installInterruptionMonitor()
        app.launch()
        app.activate()
        dismissKnownSystemDialogs(thenActivate: app)
        ensureWindowExists(in: app)

        return app
    }

    func cleanup() {
        if let interruptionMonitor {
            testCase.removeUIInterruptionMonitor(interruptionMonitor)
            self.interruptionMonitor = nil
        }

        if let fixtureRootURL {
            try? fileManager.removeItem(at: fixtureRootURL)
            self.fixtureRootURL = nil
        }
    }

    func assertDualPaneShellVisible(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.activate()
        dismissKnownSystemDialogs(thenActivate: app)

        XCTAssertTrue(element("main-content-surface", in: app).waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertTrue(element("left-file-pane", in: app).waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(element("right-file-pane", in: app).waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(element("left-file-list", in: app).waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(element("right-file-list", in: app).waitForExistence(timeout: 3), file: file, line: line)
    }

    func runToolsMenuCommand(
        _ commandTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.activate()
        dismissKnownSystemDialogs(thenActivate: app)

        let toolsMenu = app.menuBars.menuBarItems["Tools"].firstMatch
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 3), file: file, line: line)
        toolsMenu.click()

        let menuItem = app.menuBars.menuItems[commandTitle].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3), file: file, line: line)
        menuItem.click()
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func makeFixtureRoot() throws -> URL {
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("OpenPaneUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let leftURL = rootURL.appendingPathComponent("Left", isDirectory: true)
        let rightURL = rootURL.appendingPathComponent("Right", isDirectory: true)

        try fileManager.createDirectory(at: leftURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rightURL, withIntermediateDirectories: true)
        try "left".write(to: leftURL.appendingPathComponent("left-note.txt"), atomically: true, encoding: .utf8)
        try "right".write(to: rightURL.appendingPathComponent("right-note.txt"), atomically: true, encoding: .utf8)

        return rootURL
    }

    private func installInterruptionMonitor() {
        guard interruptionMonitor == nil else {
            return
        }

        interruptionMonitor = testCase.addUIInterruptionMonitor(withDescription: "System dialog") { element in
            self.dismissOpenPaneDialog(in: element, includeDescendantLabels: false)
        }
    }

    private func dismissKnownSystemDialogs(thenActivate app: XCUIApplication) {
        let notificationCenter = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        if dismissOpenPaneDialog(in: notificationCenter, includeDescendantLabels: true) {
            app.activate()
        }
    }

    private func ensureWindowExists(in app: XCUIApplication) {
        app.activate()

        if element("main-content-surface", in: app).waitForExistence(timeout: 8) {
            return
        }

        guard !app.windows.firstMatch.waitForExistence(timeout: 2) else {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        _ = element("main-content-surface", in: app).waitForExistence(timeout: 8)
    }

    private func dismissOpenPaneDialog(in element: XCUIElement, includeDescendantLabels: Bool) -> Bool {
        if let application = element as? XCUIApplication,
           application.state == .notRunning {
            return false
        }

        guard element.exists else {
            return false
        }

        var labels = element.label
        if includeDescendantLabels {
            labels = ([labels] + element.staticTexts.allElementsBoundByIndex.map(\.label))
                .joined(separator: "\n")
        }

        guard labels.localizedCaseInsensitiveContains("OpenPane")
            || labels.localizedCaseInsensitiveContains("cpcr.kcl.OpenPane") else {
            return false
        }

        for title in ["OK", "Cancel", "Not Now", "Don't Allow"] {
            let button = element.buttons[title].firstMatch
            if button.exists {
                button.click()
                return true
            }
        }

        return false
    }

}
