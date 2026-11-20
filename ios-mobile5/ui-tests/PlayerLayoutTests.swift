import XCTest

final class PlayerLayoutTests:XCTestCase {
    func testPortraitLandscapeAndReturn() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-layout-test","-aston.mobile5.fill","NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let video=app.otherElements["videoSurface"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout:15))
        let portrait=app.windows.firstMatch.frame
        XCTAssertGreaterThan(video.frame.height,portrait.height*0.35)
        XCTAssertTrue(app.buttons["videoFit"].exists)
        app.buttons["videoFit"].tap()
        XCTAssertTrue(app.staticTexts["Изрязани краища"].exists)
        attach(app,"portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let wide=NSPredicate { _,_ in video.frame.width>video.frame.height }
        expectation(for:wide,evaluatedWith:nil)
        waitForExpectations(timeout:10)
        XCTAssertGreaterThan(video.frame.width,app.windows.firstMatch.frame.width*0.95)
        XCTAssertGreaterThan(video.frame.height,app.windows.firstMatch.frame.height*0.90)
        attach(app,"landscape")
        XCUIDevice.shared.orientation = .portrait
        let tall=NSPredicate { _,_ in app.windows.firstMatch.frame.height>app.windows.firstMatch.frame.width }
        expectation(for:tall,evaluatedWith:nil)
        waitForExpectations(timeout:10)
        XCTAssertGreaterThan(video.frame.height,app.windows.firstMatch.frame.height*0.35)
        XCTAssertLessThan(video.frame.height,app.windows.firstMatch.frame.height*0.65)
        attach(app,"portrait-return")
    }
    private func attach(_ app:XCUIApplication,_ name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
