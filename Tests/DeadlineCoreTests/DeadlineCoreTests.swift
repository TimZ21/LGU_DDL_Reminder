import Foundation
#if canImport(XCTest)
import XCTest
#endif
import DeadlineCore

final class DeadlineCoreTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func feed(_ body: String) -> String { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + body + "\r\nEND:VCALENDAR" }
    func event(_ body: String) -> String { "BEGIN:VEVENT\r\n" + body + "\r\nEND:VEVENT" }

    func testCourseCalendarImportsWeeklyMeetingsAndExceptions() throws {
        let text = feed(event("UID:class-1\r\nSUMMARY:CIE6007 Machine Learning\r\nLOCATION:TA 101\r\nDTSTART;TZID=Asia/Shanghai:20260907T143000\r\nDTEND;TZID=Asia/Shanghai:20260907T161500\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261216T235900\r\nEXDATE;TZID=Asia/Shanghai:20261007T143000"))
        let meetings = try CourseCalendarParser().parse(text, source: .subscription, timeZone: zone).meetings
        XCTAssertEqual(meetings.count, 2)
        XCTAssertTrue(meetings.allSatisfy { $0.location == "TA 101" && $0.startMinute == 14 * 60 + 30 && $0.endMinute == 16 * 60 + 15 })
        let monday = meetings.first { $0.weekday == 1 }!
        let wednesday = meetings.first { $0.weekday == 3 }!
        XCTAssertTrue(monday.occurs(on: date("2026-10-05T00:00:00+08:00"), timeZone: zone))
        XCTAssertTrue(!wednesday.occurs(on: date("2026-10-07T00:00:00+08:00"), timeZone: zone))
        XCTAssertTrue(wednesday.occurs(on: date("2026-10-14T00:00:00+08:00"), timeZone: zone))
    }

    func testCourseCalendarKeepsSeparateSessionsWithoutTaskMatching() throws {
        let body = event("UID:one\r\nSUMMARY:Machine Learning\r\nDTSTART:20261012T090000\r\nDTEND:20261012T100000") + "\r\n" +
            event("UID:two\r\nSUMMARY:Machine Learning\r\nDTSTART:20261012T090000\r\nDTEND:20261012T100000")
        let result = try CourseCalendarParser().parse(feed(body), source: .file, timeZone: zone)
        XCTAssertEqual(result.meetings.count, 2)
        XCTAssertTrue(result.meetings[0].id != result.meetings[1].id)
    }

    func testCourseCalendarPreservesUserEditForBlackboardEvent() throws {
        let first = feed(event("UID:course-a\r\nSUMMARY:Machine Learning\r\nDTSTART:20261012T090000\r\nDTEND:20261012T100000\r\nRRULE:FREQ=WEEKLY;COUNT=4"))
        let changed = feed(event("UID:course-a\r\nSUMMARY:Machine Learning\r\nDTSTART:20261012T093000\r\nDTEND:20261012T103000\r\nRRULE:FREQ=WEEKLY;COUNT=4"))
        let original = try CourseCalendarParser().parse(first, source: .blackboard, timeZone: zone).meetings.first!
        let refreshed = try CourseCalendarParser().parse(changed, source: .blackboard, timeZone: zone).meetings.first!
        XCTAssertEqual(original.id, refreshed.id)
        var schedule = CourseSchedule()
        schedule.meetings = [original]
        var edited = original; edited.location = "Room 203"
        schedule.overrides[original.id] = edited
        schedule.meetings = [refreshed]
        XCTAssertEqual(schedule.visibleMeetings.first?.location, "Room 203")
        XCTAssertEqual(schedule.visibleMeetings.first?.startMinute, 9 * 60)
    }

    func testSISCalendarChineseTimeZoneAndCount() throws {
        let text = "BEGIN:VCALENDAR\rVERSION:2.0\rBEGIN:VEVENT\rUID:sis-class\rDTSTART;TZID=\"中国标准时间\":20260908T180000\rDTEND;TZID=\"中国标准时间\":20260908T193000\rRRULE:FREQ=WEEKLY;COUNT=15;BYDAY=TU\rSUMMARY;LANGUAGE=zh-cn:CIE6007 - Machine Learning\rLOCATION:XILI CAMPUS 6E506\rEND:VEVENT\rEND:VCALENDAR"
        let meetings = try CourseCalendarParser().parse(text, source: .sis, timeZone: zone).meetings
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(meetings[0].weekday, 2)
        XCTAssertEqual(meetings[0].course, "CIE6007 - Machine Learning")
        XCTAssertTrue(meetings[0].occurs(on: date("2026-10-06T00:00:00+08:00"), timeZone: zone))
        XCTAssertFalse(meetings[0].occurs(on: date("2026-12-22T00:00:00+08:00"), timeZone: zone))
    }

    func testOutlookMailExtractsDateOnlyAndPreciseTimeWithoutGuessing() {
        let messages = [
            MailMessage(id: "registration", subject: "CIE6006 Project Team Registration",
                        body: "Registration Deadline: October 31", sender: "ta@school.edu",
                        receivedAt: date("2026-09-21T10:00:00Z")),
            MailMessage(id: "homework", subject: "CIE6007 Homework 1",
                        body: "The due date is 19th October, by 11:59 PM.", sender: "ta@school.edu",
                        receivedAt: date("2026-10-04T00:00:00Z"))
        ]
        let found = MailDeadlineExtractor().candidates(from: messages, timeZone: zone, now: date("2026-10-09T00:00:00Z"))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].dueDate, date("2026-10-19T23:59:00+08:00"))
        XCTAssertTrue(found[0].hasTime)
        XCTAssertEqual(found[1].dueDate, date("2026-10-31T00:00:00+08:00"))
        XCTAssertFalse(found[1].hasTime)
        XCTAssertEqual(found[1].course, "CIE6006")
    }

    func testOutlookCandidateDoesNotGetConsumedByCalendarSync() {
        let mail = Deadline(id: "outlook:one:1", title: "Homework", dueDate: date("2026-10-19T00:00:00Z"), source: .outlook)
        let calendar = Deadline(id: "blackboard:one", title: "Homework", dueDate: mail.dueDate, source: .blackboard)
        let merged = DeadlineMerger.merge(previous: [mail], parsed: ParsedCalendar(deadlines: [calendar], warnings: [], protectedPrefixes: []), source: .blackboard)
        XCTAssertEqual(Set(merged.map(\.source)), Set([.outlook, .blackboard]))
    }

    func testRepeatedMailCandidatesRemainSeparateForHumanReview() {
        let mail = MailMessage(id: "same", subject: "Homework due", body: "Due October 19",
                               sender: "ta@school.edu", receivedAt: date("2026-10-09T00:00:00Z"))
        let found = MailDeadlineExtractor().candidates(from: [mail, mail], timeZone: zone,
                                                       now: date("2026-10-09T00:00:00Z"))
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found[0].id != found[1].id)
    }

    func testOutlookEMLImportReadsMultipartTextAndStableIdentity() throws {
        let eml = """
        From: TA <ta@example.edu>\r
        Subject: CIE6006 Project Team Registration\r
        Date: Mon, 21 Sep 2026 17:55:00 +0800\r
        MIME-Version: 1.0\r
        Content-Type: multipart/alternative; boundary="part123"\r
        \r
        --part123\r
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        Registration Deadline: October 31\r
        --part123\r
        Content-Type: text/html; charset="UTF-8"\r
        \r
        <p>Registration Deadline: November 1</p>\r
        --part123--\r
        """
        let data = Data(eml.utf8)
        let message = try EMLParser().parse(data)
        XCTAssertEqual(message, try EMLParser().parse(data))
        XCTAssertEqual(message.subject, "CIE6006 Project Team Registration")
        XCTAssertTrue(message.body.contains("October 31"))
        XCTAssertFalse(message.body.contains("November 1"))
        let found = MailDeadlineExtractor().candidates(from: [message], timeZone: zone, now: date("2026-10-09T00:00:00Z"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].dueDate, date("2026-10-31T00:00:00+08:00"))
    }

    func testOutlookEMLImportReadsNestedMultipartWithoutAttachment() throws {
        let eml = """
        From: TA <ta@example.edu>
        Subject: CIE6006 Registration
        Date: Mon, 21 Sep 2026 17:55:00 +0800
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: multipart/alternative; boundary="inner"

        --inner
        Content-Type: text/html; charset="UTF-8"

        <p>Registration Deadline: November 1</p>
        --inner
        Content-Type: text/plain; charset="UTF-8"

        Registration Deadline: October 31
        --inner--
        --outer
        Content-Type: text/plain
        Content-Disposition: attachment; filename="notes.txt"

        Deadline: December 1
        --outer--
        """
        let message = try EMLParser().parse(Data(eml.utf8))
        XCTAssertTrue(message.body.contains("October 31"))
        XCTAssertFalse(message.body.contains("November 1"))
        XCTAssertFalse(message.body.contains("December 1"))
    }

    func testUTCConvertsToBeijingWithoutShiftingInstant() throws {
        let result = try ICalendarParser().parse(feed(event("UID:a\r\nSUMMARY:Homework\r\nDTSTART:20261009T155900Z")))
        XCTAssertEqual(result.deadlines[0].dueDate, date("2026-10-09T23:59:00+08:00"))
        XCTAssertTrue(result.deadlines[0].hasTime)
    }
    func testTZIDAndFloatingDate() throws {
        let body = event("UID:a\r\nDTSTART;TZID=Asia/Hong_Kong:20261009T235900") + "\r\n" + event("UID:b\r\nDTSTART:20261009T235900")
        let result = try ICalendarParser().parse(feed(body), defaultTimeZone: zone)
        XCTAssertEqual(result.deadlines.map(\.dueDate), [date("2026-10-09T23:59:00+08:00"), date("2026-10-09T23:59:00+08:00")])
    }
    func testAllDayNeverInventsMidnightDeadline() throws {
        let result = try ICalendarParser().parse(feed(event("UID:all\r\nDTSTART;VALUE=DATE:20261009")))
        let item = result.deadlines[0]
        XCTAssertFalse(item.hasTime)
        XCTAssertFalse(item.isOverdue(at: date("2026-10-09T23:59:00+08:00"), timeZone: zone))
        XCTAssertTrue(item.isOverdue(at: date("2026-10-10T00:00:00+08:00"), timeZone: zone))
        let plans = ReminderPlanner.plans(for: [item], preferences: Preferences(), now: date("2026-10-07T00:00:00+08:00"))
        XCTAssertEqual(plans.map(\.fireDate), [date("2026-10-08T09:00:00+08:00"), date("2026-10-09T09:00:00+08:00")])
        XCTAssertTrue(plans.allSatisfy { $0.subtitle.contains("待确认") })
    }
    func testFoldedUnicodeAndEscapesAndIgnoresAlarmDates() throws {
        let body = "UID:a\r\nSUMMARY:作业\\,第三\r\n 次\\;概率论\r\nDESCRIPTION:第一行\\n第二行\\\\路径\r\nDTSTART:20261009T155900Z\r\nBEGIN:VALARM\r\nDTSTART:20260101T000000Z\r\nEND:VALARM"
        let result = try ICalendarParser().parse(feed(event(body)))
        XCTAssertEqual(result.deadlines[0].title, "作业,第三次;概率论")
        XCTAssertEqual(result.deadlines[0].notes, "第一行\n第二行\\路径")
        XCTAssertEqual(result.deadlines[0].dueDate, date("2026-10-09T15:59:00Z"))
    }
    func testDueOverridesStartForTodo() throws {
        let body = "BEGIN:VTODO\r\nUID:a\r\nSUMMARY:Essay\r\nDTSTART:20261001T120000Z\r\nDUE:20261009T120000Z\r\nEND:VTODO"
        let result = try ICalendarParser().parse(feed(body))
        XCTAssertEqual(result.deadlines[0].dueDate, date("2026-10-09T12:00:00Z"))
    }
    func testCancelledAndEmptyFeedAreValid() throws {
        XCTAssertTrue(try ICalendarParser().parse(feed("")).deadlines.isEmpty)
        let result = try ICalendarParser().parse(feed(event("UID:a\r\nDTSTART:20261009T120000Z\r\nSTATUS:CANCELLED")))
        XCTAssertTrue(result.deadlines.isEmpty)
    }
    func testMalformedResponseDoesNotLookLikeEmptyCalendar() {
        XCTAssertThrowsError(try ICalendarParser().parse("<html>Please sign in</html>"))
        XCTAssertThrowsError(try ICalendarParser().parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR"))
    }
    func testUnknownTimezoneAndInvalidDateAreFlagged() throws {
        let result = try ICalendarParser().parse(feed(event("UID:a\r\nDTSTART;TZID=Unknown/Zone:20261009T235900") + "\r\n" + event("UID:b\r\nDTSTART:20260230T235900")))
        XCTAssertTrue(result.deadlines.isEmpty)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertEqual(Set(result.protectedPrefixes), Set(["blackboard:a", "blackboard:b"]))
    }
    func testWeeklyRecurrenceExdatesAndMovedOverride() throws {
        let base = event("UID:repeat\r\nSUMMARY:Weekly\r\nDTSTART;TZID=Asia/Shanghai:20261005T180000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4\r\nEXDATE;TZID=Asia/Shanghai:20261007T180000")
        let moved = event("UID:repeat\r\nSUMMARY:Moved\r\nRECURRENCE-ID;TZID=Asia/Shanghai:20261012T180000\r\nDTSTART;TZID=Asia/Shanghai:20261013T190000")
        let result = try ICalendarParser().parse(feed(base + "\r\n" + moved), now: date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(result.deadlines.map(\.dueDate), [date("2026-10-05T18:00:00+08:00"), date("2026-10-13T19:00:00+08:00"), date("2026-10-14T18:00:00+08:00")])
        XCTAssertEqual(result.deadlines.count, 3)
        XCTAssertTrue(result.warnings.isEmpty)
    }
    func testCancelledRecurrenceOverrideRemovesOnlyOneOccurrence() throws {
        let base = event("UID:repeat\r\nDTSTART:20261005T180000Z\r\nRRULE:FREQ=DAILY;COUNT=3")
        let cancelled = event("UID:repeat\r\nRECURRENCE-ID:20261006T180000Z\r\nDTSTART:20261006T180000Z\r\nSTATUS:CANCELLED")
        let result = try ICalendarParser().parse(feed(base + "\r\n" + cancelled), now: date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(result.deadlines.count, 2)
        XCTAssertFalse(result.deadlines.contains { $0.dueDate == date("2026-10-06T18:00:00Z") })
    }
    func testRecurrencePreservesLocalHourAcrossDST() throws {
        let body = "UID:dst\r\nDTSTART;TZID=America/New_York:20261031T180000\r\nRRULE:FREQ=DAILY;COUNT=3"
        let result = try ICalendarParser().parse(feed(event(body)), now: date("2026-10-30T00:00:00Z"))
        XCTAssertEqual(result.deadlines.map(\.dueDate), [date("2026-10-31T22:00:00Z"), date("2026-11-01T23:00:00Z"), date("2026-11-02T23:00:00Z")])
    }
    func testUnsupportedRecurrenceIsVisibleWarning() throws {
        let result = try ICalendarParser().parse(feed(event("UID:monthly\r\nDTSTART:20261001T180000Z\r\nRRULE:FREQ=MONTHLY;BYSETPOS=-1")))
        XCTAssertTrue(result.deadlines.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.protectedPrefixes, ["blackboard:monthly"])
    }
    func testReminderOffsetsCompletionAndNoPastAlerts() {
        let now = date("2026-10-09T00:00:00Z")
        let item = Deadline(title: "Homework", dueDate: now.addingTimeInterval(7200))
        let plans = ReminderPlanner.plans(for: [item], preferences: Preferences(), now: now)
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.map(\.fireDate), [now.addingTimeInterval(5400), now.addingTimeInterval(7200)])
        var done = item; done.completed = true
        XCTAssertTrue(ReminderPlanner.plans(for: [done], preferences: Preferences(), now: now).isEmpty)
        var off = Preferences(); off.notificationsEnabled = false
        XCTAssertTrue(ReminderPlanner.plans(for: [item], preferences: off, now: now).isEmpty)
    }
    func testMergeRemovesDeletedPreservesCompletionAfterRescheduleAndProtectsFailures() {
        let due = date("2026-10-09T00:00:00Z")
        let completed = Deadline(id: "blackboard:one", title: "One", dueDate: due, source: .blackboard, completed: true)
        let removed = Deadline(id: "blackboard:removed", title: "Removed", dueDate: due, source: .blackboard)
        let failed = Deadline(id: "blackboard:failed", title: "Failed", dueDate: due, source: .blackboard)
        let manual = Deadline(title: "Manual", dueDate: due)
        var fresh = completed; fresh.completed = false
        let parsed = ParsedCalendar(deadlines: [fresh], warnings: ["failure"], protectedPrefixes: ["blackboard:failed"])
        let merged = DeadlineMerger.merge(previous: [completed, removed, failed, manual], parsed: parsed, source: .blackboard)
        XCTAssertEqual(merged.count, 3)
        XCTAssertTrue(merged.first { $0.id == completed.id }!.completed)
        XCTAssertTrue(merged.contains { $0.id == manual.id })
        fresh.dueDate = due.addingTimeInterval(3600)
        let changed = DeadlineMerger.merge(previous: [completed], parsed: ParsedCalendar(deadlines: [fresh], warnings: [], protectedPrefixes: []), source: .blackboard)
        XCTAssertTrue(changed[0].completed)
        XCTAssertEqual(changed[0].dueDate, fresh.dueDate)
    }
    func testAddressValidationAndWebcalUpgrade() throws {
        XCTAssertEqual(try FeedAddress.validate("webcal://bb.cuhk.edu.cn/calendar/feed.ics").scheme, "https")
        for invalid in ["https://bb.cuhk.edu.cn", "http://bb.cuhk.edu.cn/a.ics", "https://name:password@bb.cuhk.edu.cn/a.ics", "file:///tmp/a.ics"] {
            XCTAssertThrowsError(try FeedAddress.validate(invalid))
        }
    }

    func testReimportWithRegeneratedUIDsPreservesCompletionAndSuppressesReminders() throws {
        let now = date("2026-10-09T00:00:00Z")
        func calendar(_ revision: String) -> String {
            feed(event("UID:past-\(revision)\r\nSUMMARY:Past assignment\r\nCATEGORIES:CSC1000\r\nDTSTART:20261008T120000Z\r\nDESCRIPTION:Revision \(revision)") + "\r\n" +
                 event("UID:future-\(revision)\r\nSUMMARY:Future assignment\r\nCATEGORIES:CSC1000\r\nDTSTART:20261012T120000Z\r\nDESCRIPTION:Revision \(revision)") + "\r\n" +
                 event("UID:pending-\(revision)\r\nSUMMARY:Pending assignment\r\nCATEGORIES:CSC1000\r\nDTSTART:20261013T120000Z"))
        }
        let parser = ICalendarParser()
        var saved = Snapshot()
        saved.deadlines = try parser.parse(calendar("first"), now: now).deadlines
        for index in saved.deadlines.indices where saved.deadlines[index].title != "Pending assignment" {
            saved.deadlines[index].completed = true
        }
        // Round-trip saved data as the app does when restarted, then import a new export.
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(saved))
        let incoming = try parser.parse(calendar("second"), now: now)
        XCTAssertTrue(Set(restored.deadlines.map(\.id)).isDisjoint(with: incoming.deadlines.map(\.id)))
        let merged = DeadlineMerger.merge(previous: restored.deadlines, parsed: incoming, source: .blackboard)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.filter(\.completed).map(\.title), ["Past assignment", "Future assignment"])
        XCTAssertEqual(merged.filter { !$0.completed }.map(\.title), ["Pending assignment"])
        XCTAssertTrue(merged.filter { !$0.completed && $0.isOverdue(at: now, timeZone: zone) }.isEmpty)
        XCTAssertTrue(merged.first { $0.title == "Future assignment" }!.notes.contains("second"))
        let plans = ReminderPlanner.plans(for: merged, preferences: Preferences(), now: now)
        XCTAssertTrue(plans.allSatisfy { $0.deadline.title == "Pending assignment" })
        XCTAssertEqual(plans.count, 4)
    }

    func testUIDLessExportMetadataChangesKeepLocalCompletion() throws {
        let now = date("2026-10-09T00:00:00Z")
        let parser = ICalendarParser()
        let first = feed(event("SUMMARY:Homework\r\nCATEGORIES:Math\r\nDTSTART:20261012T120000Z\r\nDTSTAMP:20261009T000000Z\r\nDESCRIPTION:Old notes"))
        let second = feed(event("DTSTAMP:20261009T010000Z\r\nSUMMARY:Homework\r\nCATEGORIES:Math\r\nDTSTART:20261012T120000Z\r\nDESCRIPTION:Updated notes"))
        var previous = try parser.parse(first, now: now).deadlines
        previous[0].completed = true
        let incoming = try parser.parse(second, now: now)
        XCTAssertFalse(previous[0].id == incoming.deadlines[0].id)
        let merged = DeadlineMerger.merge(previous: previous, parsed: incoming, source: .blackboard)
        XCTAssertTrue(merged[0].completed)
        XCTAssertEqual(merged[0].notes, "Updated notes")
    }

    func testFileReimportsPreserveCompletionAndKeepUnrelatedTasks() throws {
        let now = date("2026-10-09T00:00:00Z")
        func calendar(_ uid: String) -> String {
            feed(event("UID:\(uid)\r\nSUMMARY:Imported homework\r\nCATEGORIES:Math\r\nDTSTART:20261012T120000Z"))
        }
        let parser = ICalendarParser()
        var previous = try parser.parse(calendar("old"), source: .file, now: now).deadlines
        previous[0].completed = true
        let unrelated = Deadline(id: "file:another-course", title: "Other course", dueDate: date("2026-10-13T12:00:00Z"), source: .file)
        let manual = Deadline(title: "Manual", dueDate: date("2026-10-14T12:00:00Z"), completed: true)
        previous += [unrelated, manual]
        let incoming = try parser.parse(calendar("new"), source: .file, now: now)
        let merged = DeadlineMerger.merge(previous: previous, parsed: incoming, source: .file, removeMissing: false)
        XCTAssertEqual(merged.count, 3)
        XCTAssertTrue(merged.first { $0.title == "Imported homework" }!.completed)
        XCTAssertTrue(merged.contains(unrelated))
        XCTAssertTrue(merged.contains(manual))
        XCTAssertFalse(merged.contains { $0.id == "file:old" })
    }

    func testFileAndSubscriptionImportsShareCompletionWithoutDuplicates() throws {
        let now = date("2026-10-09T00:00:00Z")
        func calendar(_ uid: String, title: String = "Shared homework") -> String {
            feed(event("UID:\(uid)\r\nSUMMARY:\(title)\r\nCATEGORIES:Math\r\nDTSTART:20261012T120000Z"))
        }
        let parser = ICalendarParser()
        for uid in ["original", "regenerated"] {
            var previous = try parser.parse(calendar("original"), now: now).deadlines
            previous[0].completed = true
            // A manual item with the same content is a separate user-created task.
            let manual = Deadline(title: previous[0].title, course: previous[0].course, dueDate: previous[0].dueDate)
            let incoming = try parser.parse(calendar(uid), source: .file, now: now)
            let merged = DeadlineMerger.merge(previous: previous + [manual], parsed: incoming, source: .file, removeMissing: false)
            XCTAssertEqual(merged.count, 2)
            XCTAssertTrue(merged.contains(manual))
            let synced = merged.first { $0.source == .blackboard }!
            XCTAssertTrue(synced.completed)
            XCTAssertEqual(synced.id, previous[0].id)
        }
        var file = try parser.parse(calendar("original"), source: .file, now: now).deadlines
        file[0].completed = true
        // Stable UID matching also keeps completion when the source updates task text.
        let incoming = try parser.parse(calendar("original", title: "Updated homework"), now: now)
        let merged = DeadlineMerger.merge(previous: file, parsed: incoming, source: .blackboard)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].source, .blackboard)
        XCTAssertEqual(merged[0].title, "Updated homework")
        XCTAssertTrue(merged[0].completed)
    }

    func testCompletionMatchingKeepsRecurrencesAndAmbiguousTasksSeparate() throws {
        let now = date("2026-10-09T00:00:00Z")
        let parser = ICalendarParser()
        let recurring = feed(event("UID:weekly\r\nSUMMARY:Weekly homework\r\nDTSTART:20261012T120000Z\r\nRRULE:FREQ=WEEKLY;COUNT=2"))
        let incoming = try parser.parse(recurring, now: now)
        var previous = incoming.deadlines
        previous[0].completed = true
        let merged = DeadlineMerger.merge(previous: previous, parsed: incoming, source: .blackboard)
        XCTAssertTrue(merged[0].completed)
        XCTAssertFalse(merged[1].completed)
        XCTAssertEqual(Set(ReminderPlanner.plans(for: merged, preferences: Preferences(), now: now).map { $0.deadline.id }), [merged[1].id])

        let due = date("2026-10-12T12:00:00Z")
        let ambiguous = [Deadline(id: "blackboard:a", title: "Homework", course: "Math", dueDate: due, source: .blackboard, completed: true),
                         Deadline(id: "blackboard:b", title: "Homework", course: "Math", dueDate: due, source: .blackboard)]
        let fresh = [Deadline(id: "blackboard:c", title: "Homework", course: "Math", dueDate: due, source: .blackboard),
                     Deadline(id: "blackboard:d", title: "Homework", course: "Math", dueDate: due, source: .blackboard)]
        let result = DeadlineMerger.merge(previous: ambiguous, parsed: ParsedCalendar(deadlines: fresh, warnings: [], protectedPrefixes: []), source: .blackboard)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.completed })
        // A newly added duplicate must not steal completion from an exact-ID match.
        let withNew = DeadlineMerger.merge(previous: [ambiguous[0]], parsed: ParsedCalendar(deadlines: [ambiguous[0], fresh[0]], warnings: [], protectedPrefixes: []), source: .blackboard)
        XCTAssertTrue(withNew.first { $0.id == "blackboard:a" }!.completed)
        XCTAssertFalse(withNew.first { $0.id == "blackboard:c" }!.completed)
    }

    func testExplicitlyMarkingIncompleteSurvivesAnotherUIDChange() throws {
        let now = date("2026-10-09T00:00:00Z")
        func calendar(_ uid: String) -> String {
            feed(event("UID:\(uid)\r\nSUMMARY:Homework\r\nDTSTART:20261012T120000Z"))
        }
        let parser = ICalendarParser()
        var previous = try parser.parse(calendar("first"), now: now).deadlines
        previous[0].completed = true
        var merged = DeadlineMerger.merge(previous: previous, parsed: try parser.parse(calendar("second"), now: now), source: .blackboard)
        XCTAssertTrue(merged[0].completed)
        merged[0].completed = false
        var saved = Snapshot(); saved.deadlines = merged
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(saved))
        let next = DeadlineMerger.merge(previous: restored.deadlines, parsed: try parser.parse(calendar("third"), now: now), source: .blackboard)
        XCTAssertFalse(next[0].completed)
        XCTAssertEqual(ReminderPlanner.plans(for: next, preferences: Preferences(), now: now).count, 4)
    }

    func testLocalCourseLabelSurvivesSyncAndUIDChanges() throws {
        let now = date("2026-10-09T00:00:00Z")
        func calendar(_ uid: String) -> ParsedCalendar {
            try! ICalendarParser().parse(feed(event("UID:\(uid)\r\nSUMMARY:Problem set 1\r\nDTSTART:20261012T120000Z")), now: now)
        }
        var labeled = calendar("first").deadlines[0]
        labeled.sourceCourse = labeled.course
        labeled.course = "MAT2040"
        var snapshot = Snapshot(); snapshot.deadlines = [labeled]
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        let first = DeadlineMerger.merge(previous: restored.deadlines, parsed: calendar("second"), source: .blackboard)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].course, "MAT2040")
        XCTAssertEqual(first[0].sourceCourse, "")
        let second = DeadlineMerger.merge(previous: first, parsed: calendar("third"), source: .blackboard)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].course, "MAT2040")
    }

    func testLegacySavedPreferencesMigrateWithoutLosingTasks() throws {
        var original = Snapshot()
        original.preferences.syncMinutes = 30
        original.preferences.reminderMinutes = [60, 0]
        original.preferences.notificationsEnabled = false
        original.lastSync = date("2026-10-09T06:00:00Z")
        original.deadlines = [Deadline(id: "blackboard:existing", title: "已有作业", course: "CSC3100",
                                       dueDate: date("2026-10-12T15:59:00Z"), source: .blackboard, completed: true)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var oldPreferences = json["preferences"] as! [String: Any]
        oldPreferences.removeValue(forKey: "language"); json["preferences"] = oldPreferences
        var loaded = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.deadlines, original.deadlines)
        XCTAssertEqual(loaded.lastSync, original.lastSync)
        XCTAssertEqual(loaded.preferences, original.preferences)
        XCTAssertEqual(loaded.preferences.language, .chinese)
        loaded.preferences.language = .english
        let restarted = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(loaded))
        XCTAssertEqual(restarted.preferences.language, .english)
        XCTAssertEqual(restarted.deadlines, original.deadlines)
        XCTAssertEqual(restarted.preferences.reminderMinutes, [60, 0])
        XCTAssertFalse(restarted.preferences.notificationsEnabled)
    }

    func testLanguageChangePreservesReminderInstantsAndIdentifiers() {
        let now = date("2026-10-09T00:00:00Z")
        let items = [Deadline(title: "作业 Homework", dueDate: date("2026-10-12T15:59:00Z")),
                     Deadline(title: "Project", dueDate: date("2026-10-14T00:00:00+08:00"), hasTime: false)]
        var preferences = Preferences()
        let chinese = ReminderPlanner.plans(for: items, preferences: preferences, now: now)
        preferences.language = .english
        let english = ReminderPlanner.plans(for: items, preferences: preferences, now: now)
        XCTAssertEqual(chinese.map(\.id), english.map(\.id))
        XCTAssertEqual(chinese.map(\.fireDate), english.map(\.fireDate))
        XCTAssertEqual(chinese.map(\.deadline), english.map(\.deadline))
        XCTAssertTrue(english.contains { $0.subtitle == "Due in 1 day" })
        XCTAssertTrue(english.contains { $0.subtitle == "Due today · Time to confirm" })
        XCTAssertTrue(english.contains { $0.subtitle == "Deadline reached" })
    }

    func testShenzhenLabelKeepsExistingTimeZoneAndDates() {
        var preferences = Preferences()
        XCTAssertEqual(preferences.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(preferences.timeZoneLabel, "深圳 (UTC+8)")
        preferences.language = .english
        XCTAssertEqual(preferences.timeZoneLabel, "Shenzhen (UTC+8)")
        XCTAssertEqual(preferences.timeZone.secondsFromGMT(for: date("2026-10-09T00:00:00Z")), 28800)
        let formatter = DateFormatter(); formatter.locale = preferences.language.locale
        formatter.timeZone = preferences.timeZone
        formatter.dateFormat = preferences.language.datePattern("yyyy年M月d日 EEEE HH:mm:ss")
        XCTAssertEqual(formatter.string(from: date("2026-10-09T15:59:00Z")), "Friday, 9 October 2026 23:59:00")
    }

    func testEnglishParserKeepsOriginalCourseContentAndLocalizesErrors() throws {
        let valid = event("UID:one\r\nSUMMARY:第三次作业\r\nCATEGORIES:概率论\r\nDTSTART:20261009T155900Z")
        let invalid = event("UID:bad\r\nSUMMARY:Check time\r\nDTSTART;TZID=Unknown/Zone:20261009T235900")
        let result = try ICalendarParser(language: .english).parse(feed(valid + "\r\n" + invalid))
        XCTAssertEqual(result.deadlines[0].title, "第三次作业")
        XCTAssertEqual(result.deadlines[0].course, "概率论")
        XCTAssertEqual(result.deadlines[0].dueDate, date("2026-10-09T15:59:00Z"))
        XCTAssertTrue(result.warnings[0].contains("Unsupported time zone"))
        XCTAssertEqual(result.protectedPrefixes, ["blackboard:bad"])
    }

    func testLegacyRemindersMigrationPreservesTasksAndDefaultsToOff() throws {
        var snapshot = Snapshot()
        snapshot.deadlines = [Deadline(id: "blackboard:legacy", title: "旧作业", course: "CSC", notes: "备注",
                                      dueDate: date("2026-10-12T15:59:00Z"), source: .blackboard, completed: true)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        json.removeValue(forKey: "appleReminders")
        var items = json["deadlines"] as! [[String: Any]]
        items[0].removeValue(forKey: "reminderID"); json["deadlines"] = items
        var prefs = json["preferences"] as! [String: Any]
        prefs.removeValue(forKey: "appleRemindersEnabled"); json["preferences"] = prefs
        let migrated = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(migrated.preferences.appleRemindersEnabled)
        XCTAssertEqual(migrated.appleReminders, AppleRemindersState())
        XCTAssertTrue(migrated.deadlines[0].completed)
        XCTAssertEqual(migrated.deadlines[0].dueDate, snapshot.deadlines[0].dueDate)
        XCTAssertEqual(migrated.deadlines[0].notes, "备注")
        XCTAssertTrue(UUID(uuidString: migrated.deadlines[0].reminderID) != nil)
        let restarted = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(restarted.deadlines, migrated.deadlines)
    }

    func testRemindersIdentitySurvivesUIDChangesReschedulesAndFileImport() throws {
        let parser = ICalendarParser()
        let now = date("2026-10-09T00:00:00Z")
        let initial = try parser.parse(feed(event("UID:old\r\nSUMMARY:Homework\r\nCATEGORIES:CSC\r\nDTSTART:20261012T155900Z")), now: now).deadlines
        let changed = try parser.parse(feed(event("UID:new\r\nSUMMARY:Homework\r\nCATEGORIES:CSC\r\nDTSTART:20261012T155900Z")), now: now)
        let merged = DeadlineMerger.merge(previous: initial, parsed: changed, source: .blackboard)
        XCTAssertEqual(merged[0].reminderID, initial[0].reminderID)
        XCTAssertFalse(merged[0].id == initial[0].id)
        let moved = try parser.parse(feed(event("UID:new\r\nSUMMARY:Updated homework\r\nCATEGORIES:CSC\r\nDTSTART:20261013T155900Z")), now: now)
        let rescheduled = DeadlineMerger.merge(previous: merged, parsed: moved, source: .blackboard)
        XCTAssertEqual(rescheduled[0].reminderID, initial[0].reminderID)
        let file = try parser.parse(feed(event("UID:new\r\nSUMMARY:Updated homework\r\nCATEGORIES:CSC\r\nDTSTART:20261013T155900Z")), source: .file, now: now)
        let imported = DeadlineMerger.merge(previous: rescheduled, parsed: file, source: .file, removeMissing: false)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].reminderID, initial[0].reminderID)
        XCTAssertEqual(imported[0].source, .blackboard)
    }

    func testRemindersRecurrenceAndAmbiguousTasksHaveSeparateIdentities() throws {
        let recurrence = try ICalendarParser().parse(feed(event("UID:repeat\r\nSUMMARY:Weekly\r\nDTSTART:20261012T120000Z\r\nRRULE:FREQ=DAILY;COUNT=3")), now: date("2026-10-09T00:00:00Z"))
        XCTAssertEqual(Set(recurrence.deadlines.map(\.reminderID)).count, 3)
        let a = Deadline(id: "blackboard:a", title: "Same", dueDate: date("2026-10-12T12:00:00Z"), source: .blackboard)
        let b = Deadline(id: "blackboard:b", title: "Same", dueDate: a.dueDate, source: .blackboard)
        let replacement = Deadline(id: "blackboard:c", title: "Same", dueDate: a.dueDate, source: .blackboard)
        let result = DeadlineMerger.merge(previous: [a, b], parsed: ParsedCalendar(deadlines: [replacement], warnings: [], protectedPrefixes: []), source: .blackboard)
        XCTAssertFalse([a.reminderID, b.reminderID].contains(result[0].reminderID))
    }

    func testRemindersCompletionImportsChangesAndPreservesLocalIntent() {
        XCTAssertTrue(AppleRemindersPlanner.completion(local: false, remote: true, lastSynced: false))
        XCTAssertFalse(AppleRemindersPlanner.completion(local: true, remote: false, lastSynced: true))
        XCTAssertTrue(AppleRemindersPlanner.completion(local: true, remote: false, lastSynced: false))
        XCTAssertFalse(AppleRemindersPlanner.completion(local: false, remote: true, lastSynced: true))
        XCTAssertTrue(AppleRemindersPlanner.completion(local: true, remote: false, lastSynced: nil))
        XCTAssertFalse(AppleRemindersPlanner.completion(local: false, remote: true, lastSynced: nil))
        XCTAssertTrue(AppleRemindersPlanner.completion(local: true, remote: nil, lastSynced: false))
    }

    func testRemindersDueComponentsPreserveExactInstantAndDateOnly() {
        var item = Deadline(title: "Homework", dueDate: date("2026-10-12T15:59:45Z"))
        let timed = AppleRemindersPlanner.dueComponents(for: item, timeZone: zone)
        XCTAssertEqual(timed.hour, 23); XCTAssertEqual(timed.minute, 59); XCTAssertEqual(timed.second, 45)
        XCTAssertEqual(timed.timeZone, zone); XCTAssertEqual(timed.date, item.dueDate)
        let differentZone = AppleRemindersPlanner.dueComponents(for: item, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(differentZone.date, item.dueDate)
        item.hasTime = false
        let day = AppleRemindersPlanner.dueComponents(for: item, timeZone: zone)
        XCTAssertEqual(day.year, 2026); XCTAssertEqual(day.month, 10); XCTAssertEqual(day.day, 12)
        XCTAssertTrue(day.hour == nil && day.minute == nil && day.second == nil && day.timeZone == nil)
        XCTAssertEqual(day.calendar?.identifier, .gregorian)
    }

    func testRemindersLinksIdentifyOnlyOwnedTasks() {
        let id = UUID().uuidString
        XCTAssertEqual(AppleRemindersPlanner.identity(from: AppleRemindersPlanner.link(for: id)), id)
        for value in ["https://bb.cuhk.edu.cn/calendar/feed", "shiqi://deadline/not-a-uuid", "shiqi://other/\(id)",
                      "shiqi://deadline/\(id)/extra", "shiqi://deadline/\(id)?token=private"] {
            XCTAssertTrue(AppleRemindersPlanner.identity(from: URL(string: value)) == nil)
        }
        XCTAssertTrue(AppleRemindersPlanner.link(for: "blackboard:private-feed-uid") == nil)
    }

    func testRemindersStatePersistsBaselineAndDoesNotDisableOriginalNotifications() throws {
        var snapshot = Snapshot()
        snapshot.preferences.appleRemindersEnabled = true
        let now = date("2026-10-09T00:00:00Z")
        snapshot.deadlines = [Deadline(title: "Upcoming", dueDate: now.addingTimeInterval(7200))]
        snapshot.appleReminders.calendarID = "dedicated-list"
        snapshot.appleReminders.completions[snapshot.deadlines[0].reminderID] = false
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertTrue(restored.preferences.appleRemindersEnabled)
        XCTAssertEqual(restored.appleReminders, snapshot.appleReminders)
        XCTAssertEqual(ReminderPlanner.plans(for: restored.deadlines, preferences: restored.preferences, now: now).count, 2)
        var completed = restored.deadlines
        completed[0].completed = AppleRemindersPlanner.completion(local: false, remote: true, lastSynced: false)
        XCTAssertTrue(ReminderPlanner.plans(for: completed, preferences: restored.preferences, now: now).isEmpty)
    }

    static var allTests = [
        ("课程日历每周课程和停课日期", testCourseCalendarImportsWeeklyMeetingsAndExceptions),
        ("课程日历保留独立事件", testCourseCalendarKeepsSeparateSessionsWithoutTaskMatching),
        ("Blackboard 课程同步保留手动修改", testCourseCalendarPreservesUserEditForBlackboardEvent),
        ("SIS 中文时区课表", testSISCalendarChineseTimeZoneAndCount),
        ("重复邮件候选交由人工判断", testRepeatedMailCandidatesRemainSeparateForHumanReview),
        ("Outlook 嵌套 MIME 邮件导入", testOutlookEMLImportReadsNestedMultipartWithoutAttachment),
        ("Outlook EML 文件导入", testOutlookEMLImportReadsMultipartTextAndStableIdentity),
        ("Outlook 邮件日期和具体时间", testOutlookMailExtractsDateOnlyAndPreciseTimeWithoutGuessing),
        ("Outlook 候选不被日历同步合并", testOutlookCandidateDoesNotGetConsumedByCalendarSync),
        ("提醒事项旧数据迁移默认关闭", testLegacyRemindersMigrationPreservesTasksAndDefaultsToOff),
        ("提醒事项标识跨 UID 改期与文件导入", testRemindersIdentitySurvivesUIDChangesReschedulesAndFileImport),
        ("提醒事项重复日历与歧义隔离", testRemindersRecurrenceAndAmbiguousTasksHaveSeparateIdentities),
        ("提醒事项完成与恢复待办双向同步", testRemindersCompletionImportsChangesAndPreservesLocalIntent),
        ("提醒事项具体时间与仅日期", testRemindersDueComponentsPreserveExactInstantAndDateOnly),
        ("提醒事项链接与非托管事项隔离", testRemindersLinksIdentifyOnlyOwnedTasks),
        ("提醒事项状态持久化与原通知兼容", testRemindersStatePersistsBaselineAndDoesNotDisableOriginalNotifications),
        ("UTC → 北京时间", testUTCConvertsToBeijingWithoutShiftingInstant),
        ("TZID / 无时区日期", testTZIDAndFloatingDate),
        ("仅日期事项与提醒", testAllDayNeverInventsMidnightDeadline),
        ("多行中文与转义", testFoldedUnicodeAndEscapesAndIgnoresAlarmDates),
        ("VTODO DUE", testDueOverridesStartForTodo),
        ("取消与空日历", testCancelledAndEmptyFeedAreValid),
        ("登录页面与截断文件", testMalformedResponseDoesNotLookLikeEmptyCalendar),
        ("错误时区与无效日期", testUnknownTimezoneAndInvalidDateAreFlagged),
        ("重复事项与改期", testWeeklyRecurrenceExdatesAndMovedOverride),
        ("取消单次重复事项", testCancelledRecurrenceOverrideRemovesOnlyOneOccurrence),
        ("夏令时转换", testRecurrencePreservesLocalHourAcrossDST),
        ("不支持的重复规则", testUnsupportedRecurrenceIsVisibleWarning),
        ("提醒时刻与完成状态", testReminderOffsetsCompletionAndNoPastAlerts),
        ("同步合并与改期", testMergeRemovesDeletedPreservesCompletionAfterRescheduleAndProtectsFailures),
        ("订阅链接验证", testAddressValidationAndWebcalUpgrade),
        ("UID 变化后保留完成状态和提醒", testReimportWithRegeneratedUIDsPreservesCompletionAndSuppressesReminders),
        ("无 UID 导出的元数据变化", testUIDLessExportMetadataChangesKeepLocalCompletion),
        ("文件重导入保留完成状态", testFileReimportsPreserveCompletionAndKeepUnrelatedTasks),
        ("文件与在线导入共享完成状态", testFileAndSubscriptionImportsShareCompletionWithoutDuplicates),
        ("重复事项与歧义任务隔离", testCompletionMatchingKeepsRecurrencesAndAmbiguousTasksSeparate),
        ("手动恢复待办后再次同步", testExplicitlyMarkingIncompleteSurvivesAnotherUIDChange),
        ("本机课程标注在同步后保留", testLocalCourseLabelSurvivesSyncAndUIDChanges),
        ("旧版数据与语言设置迁移", testLegacySavedPreferencesMigrateWithoutLosingTasks),
        ("语言切换保留提醒时刻", testLanguageChangePreservesReminderInstantsAndIdentifiers),
        ("深圳标签与实际时区", testShenzhenLabelKeepsExistingTimeZoneAndDates),
        ("英文解析提示保留课程内容", testEnglishParserKeepsOriginalCourseContentAndLocalizesErrors)
    ]
}
