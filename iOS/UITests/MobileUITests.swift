import XCTest

final class MobileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-test-data"] : [])
        app.launch()
        return app
    }
    private func tap(_ element: XCUIElement, app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 1)
        for _ in 0..<10 {
            if !element.exists { app.swipeUp(); continue }
            if element.isHittable { break }
            if element.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
    private func selectFilter(_ name: String, app: XCUIApplication) {
        let bar = app.scrollViews["filters"]
        let heading = app.staticTexts["dashboard.heading"]
        for _ in 0..<8 {
            if bar.exists && bar.isHittable { break }
            if heading.exists && heading.frame.minY >= app.navigationBars.firstMatch.frame.maxY { break }
            app.swipeDown()
        }
        for _ in 0..<8 {
            if bar.exists && bar.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(bar.exists && bar.isHittable)
        let button = app.buttons["filter.\(name)"]
        for _ in 0..<6 {
            if button.exists && button.isHittable { break }
            if name == "upcoming" { bar.swipeRight() } else { bar.swipeLeft() }
        }
        XCTAssertTrue(button.exists && button.isHittable)
        button.tap()
    }
    @discardableResult
    private func revealTask(_ title: String, app: XCUIApplication) -> XCUIElement {
        let heading = app.staticTexts["dashboard.heading"]
        for _ in 0..<12 {
            if heading.exists && heading.frame.minY >= app.navigationBars.firstMatch.frame.maxY { break }
            app.swipeDown()
        }
        let task = app.buttons["deadline.\(title)"]
        for _ in 0..<12 {
            if task.exists && task.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(task.exists && task.isHittable)
        return task
    }
    func testCompletedImportSurvivesRegeneratedUIDAndRelaunch() {
        let app = launch()
        tap(app.buttons["test.import"], app: app)
        let task = revealTask("Fixture assignment", app: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        tap(app.buttons["complete.Fixture assignment"], app: app)
        tap(app.buttons["test.reimport"], app: app)
        XCTAssertFalse(task.exists)
        selectFilter("completed", app: app)
        revealTask("Fixture assignment", app: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "deadline.Fixture assignment").count, 1)
        app.terminate()
        let reopened = launch(reset: false)
        selectFilter("completed", app: reopened)
        revealTask("Fixture assignment", app: reopened)
        XCTAssertTrue(reopened.buttons["deadline.Fixture assignment"].waitForExistence(timeout: 5))
        tap(reopened.buttons["complete.Fixture assignment"], app: reopened)
        selectFilter("upcoming", app: reopened)
        revealTask("Fixture assignment", app: reopened)
        XCTAssertTrue(reopened.buttons["deadline.Fixture assignment"].waitForExistence(timeout: 5))
    }
    func testManualDeadlineAndEnglishPreferencePersist() {
        let app = launch()
        app.buttons["add"].tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Mobile test deadline")
        app.buttons["editor.save"].tap()
        revealTask("Mobile test deadline", app: app)
        XCTAssertTrue(app.buttons["deadline.Mobile test deadline"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.buttons["settings.language"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settings.done"].tap()
        app.terminate()
        let reopened = launch(reset: false)
        XCTAssertTrue(reopened.navigationBars["Shiqi"].waitForExistence(timeout: 5))
        revealTask("Mobile test deadline", app: reopened)
        XCTAssertTrue(reopened.buttons["deadline.Mobile test deadline"].waitForExistence(timeout: 5))
    }

    func testChineseLongContentLayoutAndSheets() { checkLayout(english: false) }
    func testEnglishLongContentLayoutAndSheets() { checkLayout(english: true) }

    private func checkLayout(english: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--layout-fixture"]
        app.launch()
        let language = english ? "English" : "Chinese"
        if english {
            tap(app.buttons["settings"], app: app)
            tap(app.buttons["settings.language"], app: app)
            app.buttons["English"].tap()
            tap(app.buttons["settings.done"], app: app)
        }
        let heading = app.staticTexts["dashboard.heading"]
        let subtitle = app.staticTexts["dashboard.subtitle"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        assertSeparate(heading, subtitle)
        capture(app, "\(language)-dashboard-header")

        let title = "Final research project: literature review, experiment analysis and revised submission / 期末研究项目：文献综述、实验分析与修订报告"
        let row = app.buttons["deadline.\(title)"]
        let completion = app.buttons["complete.\(title)"]
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.exists)
        assertSeparate(row, completion)
        XCTAssertGreaterThanOrEqual(completion.frame.width, 44)
        XCTAssertGreaterThanOrEqual(completion.frame.height, 44)
        XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        capture(app, "\(language)-long-deadline")
        tap(row, app: app)
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 5))
        capture(app, "\(language)-detail-top")
        app.swipeUp()
        capture(app, "\(language)-detail-scrolled")
        tap(app.buttons["detail.done"], app: app)

        tap(app.buttons["add"], app: app)
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        assertSeparate(app.buttons["editor.cancel"], app.buttons["editor.save"])
        capture(app, "\(language)-editor")
        for index in 1...2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
            capture(app, "\(language)-editor-scrolled-\(index)")
        }
        tap(app.buttons["editor.cancel"], app: app)
        tap(app.buttons["connection"], app: app)
        XCTAssertTrue(app.buttons["connection.done"].waitForExistence(timeout: 5))
        capture(app, "\(language)-connection")
        app.swipeUp()
        capture(app, "\(language)-connection-scrolled")
        tap(app.buttons["connection.done"], app: app)
        tap(app.buttons["settings"], app: app)
        XCTAssertTrue(app.buttons["settings.language"].waitForExistence(timeout: 5))
        capture(app, "\(language)-settings-top")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        capture(app, "\(language)-settings-middle")
        for _ in 0..<12 { app.swipeUp() }
        capture(app, "\(language)-settings-scrolled")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [landscape], timeout: 5)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        capture(app, "\(language)-settings-landscape")
        tap(app.buttons["settings.done"], app: app)
        assertSeparate(app.buttons["settings"], app.buttons["add"])
        capture(app, "\(language)-dashboard-landscape")
    }
    private func assertSeparate(_ first: XCUIElement, _ second: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(first.exists && second.exists, file: file, line: line)
        XCTAssertGreaterThan(first.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(second.frame.width, 0, file: file, line: line)
        XCTAssertTrue(first.frame.intersection(second.frame).isEmpty,
                      "Overlapping frames: \(first.frame), \(second.frame)", file: file, line: line)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
