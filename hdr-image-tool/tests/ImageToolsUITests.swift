import XCTest

final class ImageToolsUITests: XCTestCase {
    private func loadedApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--workspace-test-image", "__WORKSPACE_TEST_IMAGE__"]
        app.launch()
        XCTAssertTrue(app.staticTexts["双击图像全屏查看"].waitForExistence(timeout: 20))
        return app
    }

    func testColorDescriptionsAreVisible() {
        let app = loadedApp()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "图片状态详情")).firstMatch.tap()
        let sdr = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SDR 色域")).firstMatch
        let hdr = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "HDR 色域")).firstMatch
        let gain = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "GainMap 色域")).firstMatch
        XCTAssertTrue(sdr.waitForExistence(timeout: 10))
        XCTAssertTrue(sdr.label.contains("sRGB"))
        XCTAssertTrue(hdr.label.contains("不适用"))
        XCTAssertTrue(gain.label.contains("未提供"))
    }

    func testAdjustModeSpacingMatchesViewer() {
        let app = loadedApp()
        let importer = app.buttons["从相册选择"].firstMatch
        let viewerMode = app.segmentedControls.containing(.button, identifier: "HDR").firstMatch
        let viewerGap = viewerMode.frame.minY - importer.frame.maxY
        app.tabBars.buttons["调整"].tap()
        let adjustMode = app.segmentedControls.containing(.button, identifier: "HDR").firstMatch
        XCTAssertTrue(adjustMode.waitForExistence(timeout: 10))
        let adjustGap = adjustMode.frame.minY - importer.frame.maxY
        XCTAssertGreaterThanOrEqual(adjustGap, 16)
        XCTAssertLessThanOrEqual(abs(adjustGap - viewerGap), 4)
    }

    func testFullScreenPinchAndReopen() {
        let app = loadedApp()
        let preview = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "HDR 图像预览")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.doubleTap()
        let zoom = app.scrollViews["full-screen-preview"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 10))
        XCTAssertEqual(zoomScale(zoom), 1, accuracy: 0.05)
        zoom.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(zoomScale(zoom), 1.2)
        XCTAssertLessThanOrEqual(zoomScale(zoom), 8.05)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "全屏-实际捏合放大"
        attachment.lifetime = .keepAlways
        add(attachment)
        zoom.swipeLeft()
        app.buttons["退出全屏"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.doubleTap()
        XCTAssertTrue(zoom.waitForExistence(timeout: 10))
        XCTAssertEqual(zoomScale(zoom), 1, accuracy: 0.05)
        zoom.doubleTap()
        XCTAssertTrue(app.tabBars.buttons["查看"].waitForExistence(timeout: 10))
    }

    func testRGBYChannelsAndHSV() {
        let app = loadedApp()
        app.tabBars.buttons["分析"].tap()
        let chart = app.descendants(matching: .any).matching(identifier: "histogram-rgby").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        for name in ["R", "G", "B", "Y"] {
            let toggle = app.descendants(matching: .any).matching(identifier: "histogram-channel-\(name)").firstMatch
            XCTAssertEqual(toggle.value as? String, "显示")
        }
        let green = app.descendants(matching: .any).matching(identifier: "histogram-channel-G").firstMatch
        green.tap()
        XCTAssertEqual(green.value as? String, "隐藏")
        app.tabBars.buttons["查看"].tap()
        app.tabBars.buttons["分析"].tap()
        XCTAssertEqual(green.value as? String, "隐藏")
        app.segmentedControls.buttons["二维色度"].tap()
        app.segmentedControls.buttons["直方图"].tap()
        XCTAssertEqual(green.value as? String, "隐藏")
        for name in ["R", "B", "Y"] {
            let toggle = app.descendants(matching: .any).matching(identifier: "histogram-channel-\(name)").firstMatch
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "隐藏")
        }
        XCTAssertTrue(chart.label.contains("未选择通道"))
        for name in ["H", "S", "V"] {
            app.segmentedControls.buttons[name].tap()
            let single = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "\(name) 直方图")).firstMatch
            XCTAssertTrue(single.waitForExistence(timeout: 10))
            XCTAssertFalse(chart.exists)
        }
        app.segmentedControls.buttons["RGBY"].tap()
        XCTAssertTrue(chart.label.contains("未选择通道"))
        let red = app.descendants(matching: .any).matching(identifier: "histogram-channel-R").firstMatch
        red.tap()
        XCTAssertEqual(red.value as? String, "显示")
        XCTAssertEqual(green.value as? String, "隐藏")
    }

    private func zoomScale(_ element: XCUIElement) -> Double {
        let value = element.value as? String ?? ""
        return Double(value.filter { "0123456789.".contains($0) }) ?? 0
    }
}
