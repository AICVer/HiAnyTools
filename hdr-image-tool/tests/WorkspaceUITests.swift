import XCTest

final class WorkspaceUITests: XCTestCase {
    func testImageImportAndWorkspaceState() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--workspace-test-image", "__WORKSPACE_TEST_IMAGE__"]
        app.launch()
        XCTAssertTrue(app.staticTexts["双击图像全屏查看"].waitForExistence(timeout: 20))
        let importer = app.buttons["从相册选择"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 10))
        importer.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["双击图像全屏查看"].waitForExistence(timeout: 20))
        saveScreen(app, name: "查看-已导入")

        app.tabBars.buttons["调整"].tap()
        app.segmentedControls.buttons["GainMap 合成"].tap()
        let gain = app.sliders["灰度最大增益"]
        XCTAssertTrue(gain.waitForExistence(timeout: 10))
        gain.adjust(toNormalizedSliderPosition: 0.3)
        let gainValue = gain.value as? String
        app.tabBars.buttons["查看"].tap()
        app.tabBars.buttons["调整"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["GainMap 合成"].isSelected)
        XCTAssertEqual(gain.value as? String, gainValue)
        saveScreen(app, name: "调整-保留增益")

        app.tabBars.buttons["分析"].tap()
        app.segmentedControls.buttons["二维色度"].tap()
        let chart = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "CIE 1931 xy 像素分布")).firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 20))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "图层设置")).firstMatch.tap()
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "当前图散点")).firstMatch.tap()
        XCTAssertTrue(chart.label.contains("原图散点0"))
        app.segmentedControls.buttons["三维色域"].tap()
        let volume = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "三维像素点云")).firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 20))
        app.segmentedControls.buttons["二维色度"].tap()
        XCTAssertTrue(chart.label.contains("原图散点0"), "切换二维/三维不应重置图层")
        app.tabBars.buttons["查看"].tap()
        app.tabBars.buttons["分析"].tap()
        XCTAssertTrue(chart.label.contains("原图散点0"), "切换功能页不应重置图层")
        saveScreen(app, name: "分析-图层保留")

        app.tabBars.buttons["导出"].tap()
        app.segmentedControls.buttons["SDR"].tap()
        let settings = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "导出参数（")).firstMatch
        settings.tap()
        let quality = app.sliders["压缩质量上限"]
        XCTAssertTrue(quality.waitForExistence(timeout: 10))
        if !quality.isHittable { app.scrollViews.firstMatch.swipeUp() }
        quality.adjust(toNormalizedSliderPosition: 0.4)
        let qualityValue = quality.value as? String
        app.tabBars.buttons["查看"].tap()
        app.tabBars.buttons["导出"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["SDR"].isSelected)
        if !quality.exists { settings.tap() }
        XCTAssertEqual(quality.value as? String, qualityValue)
        let generateSDR = app.buttons["生成 SDR JPEG"]
        if !generateSDR.isHittable { app.scrollViews.firstMatch.swipeDown() }
        generateSDR.tap()
        let sdrShare = app.buttons["保存或分享 SDR 文件"]
        XCTAssertTrue(sdrShare.waitForExistence(timeout: 20))
        app.tabBars.buttons["查看"].tap()
        app.tabBars.buttons["导出"].tap()
        XCTAssertTrue(sdrShare.exists, "有效生成文件应保留")
        app.segmentedControls.buttons["HDR"].tap()
        XCTAssertFalse(sdrShare.exists, "HDR 页不应展示 SDR 分享结果")
        app.buttons["生成 PQ PNG"].tap()
        XCTAssertTrue(app.buttons["保存或分享已生成文件"].waitForExistence(timeout: 20))
        app.segmentedControls.buttons["SDR"].tap()
        XCTAssertTrue(sdrShare.exists)
        saveScreen(app, name: "导出-SDR结果保留")
    }

    private func saveScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEmptyWorkspaceNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        for name in ["查看", "调整", "分析", "导出", "查看"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "缺少功能页：\(name)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "功能页未选中：\(name)")
            XCTAssertTrue(app.buttons["从相册选择"].firstMatch.exists,
                          "无图时仍应提供导入入口：\(name)")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "空状态-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
