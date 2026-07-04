//
//  OpenPaneUITestsLaunchTests.swift
//  OpenPaneUITests
//
//  Created by Christopher Rego on 6/4/26.
//

import XCTest

final class OpenPaneUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "main-content-surface").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "left-file-pane").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "right-file-pane").firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
