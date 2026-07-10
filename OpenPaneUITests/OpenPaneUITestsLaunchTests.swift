//
//  OpenPaneUITestsLaunchTests.swift
//  OpenPaneUITests
//
//  Created by Christopher Rego on 6/4/26.
//

import XCTest

final class OpenPaneUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let driver = OpenPaneUITestDriver(testCase: self)
        let app = try driver.launchApp()
        defer {
            driver.cleanup()
        }

        driver.assertDualPaneShellVisible(in: app)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
