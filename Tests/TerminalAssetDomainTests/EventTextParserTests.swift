import Foundation
import Testing
@testable import TerminalAssetDomain

private let utc = TimeZone(identifier: "UTC") ?? .gmt
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}()

/// Friday 2027-01-15 10:20 UTC.
private let now = Date(timeIntervalSince1970: 1_800_008_400)

private func parse(_ text: String) -> ParsedEvent {
    EventTextParser.parse(text, now: now, calendar: calendar)
}

private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2027) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
}

@Suite("EventTextParser · English")
struct EventTextParserEnglishTests {
    @Test func tomorrowWithATime() {
        let result = parse("Lunch with Anna tomorrow 12:30")
        #expect(result.draft.title == "Lunch with Anna")
        #expect(result.draft.start == at(1, 16, 12, 30))
        #expect(result.draft.end == at(1, 16, 13, 30))
        #expect(result.recognized == [.date, .time])
    }

    @Test func durationLocationAndTime() {
        let result = parse("Dentist tomorrow 3pm for 45 min at Bangkok Hospital")
        #expect(result.draft.title == "Dentist")
        #expect(result.draft.start == at(1, 16, 15))
        #expect(result.draft.end == at(1, 16, 15, 45))
        #expect(result.draft.location == "Bangkok Hospital")
        #expect(result.recognized == [.date, .time, .duration, .location])
    }

    @Test func ninetyMinutes() {
        let result = parse("Team meeting tomorrow at 3pm for 90 minutes")
        #expect(result.draft.title == "Team meeting")
        #expect(result.draft.end == at(1, 16, 16, 30))
    }

    @Test func aTimeLaterTodayStaysToday() {
        let result = parse("call mom at 8pm")
        #expect(result.draft.title == "call mom")
        #expect(result.draft.start == at(1, 15, 20))
    }

    @Test func aTimeAlreadyPassedMeansTomorrow() {
        let result = parse("call mom at 9am")
        #expect(result.draft.start == at(1, 16, 9))
    }

    @Test func aWeekdayIsTheNextOne() {
        let result = parse("standup monday 9:30")
        #expect(result.draft.title == "standup")
        #expect(result.draft.start == at(1, 18, 9, 30))
    }

    @Test func aWeekdayNamedOnThatWeekdayMeansNextWeek() {
        #expect(parse("gym friday 6pm").draft.start == at(1, 22, 18))
    }

    @Test func thisWeekdayCanBeToday() {
        #expect(parse("gym this friday 6pm").draft.start == at(1, 15, 18))
    }

    @Test func nextWeekdayIsInTheFollowingWeek() {
        // Friday 15th → the following week starts Sunday 17th → Friday 22nd.
        #expect(parse("review next friday 2pm").draft.start == at(1, 22, 14))
        // Monday of the following week, not the coming Monday of this one.
        #expect(parse("planning next monday 10am").draft.start == at(1, 18, 10))
    }

    @Test func isoDateWithATimeRange() {
        let result = parse("workshop 2027-02-03 10:00-12:00")
        #expect(result.draft.title == "workshop")
        #expect(result.draft.start == at(2, 3, 10))
        #expect(result.draft.end == at(2, 3, 12))
    }

    @Test func dayMonthSlashDate() {
        let result = parse("conference 25/2 all day")
        #expect(result.draft.isAllDay)
        #expect(result.draft.title == "conference")
        #expect(result.draft.start == at(2, 25, 0))
        #expect(result.recognized.contains(.allDay))
    }

    @Test func aPastDayMonthMeansNextYear() {
        #expect(parse("tax deadline 3 jan all day").draft.start == at(1, 3, 0, year: 2028))
    }

    @Test func monthNameDates() {
        #expect(parse("trip Sep 25 all day").draft.start == at(9, 25, 0))
        #expect(parse("trip 25th September 2028 all day").draft.start == at(9, 25, 0, year: 2028))
    }

    @Test func dayAfterTomorrow() {
        #expect(parse("visa appointment day after tomorrow 11am").draft.start == at(1, 17, 11))
    }

    @Test func aDateAloneStartsAtNine() {
        let result = parse("planning tomorrow")
        #expect(result.draft.start == at(1, 16, 9))
        #expect(result.recognized == [.date])
    }

    @Test func aRangeThatCrossesMidnightEndsTheNextDay() {
        let result = parse("party tomorrow 10pm-1am")
        #expect(result.draft.start == at(1, 16, 22))
        #expect(result.draft.end == at(1, 17, 1))
    }

    @Test func eveningWordsMakeABareHourEvening() {
        #expect(parse("dinner tonight at 8").draft.start == at(1, 15, 20))
    }

    @Test func aSmallBareHourIsTheAfternoon() {
        #expect(parse("gym at 6").draft.start == at(1, 15, 18))
    }

    @Test func noonIsNoon() {
        #expect(parse("lunch at 12pm").draft.start == at(1, 15, 12))
        #expect(parse("standup noon tomorrow").draft.start == at(1, 16, 12))
    }

    @Test func plainTextBecomesAnUndatedDraft() {
        let result = parse("buy milk")
        #expect(result.draft.title == "buy milk")
        #expect(result.recognized.isEmpty)
        #expect(result.draft.start == at(1, 15, 11))
    }

    @Test func numbersThatAreNotTimesStayInTheTitle() {
        let result = parse("Room 3 inspection")
        #expect(result.draft.title == "Room 3 inspection")
        #expect(result.recognized.isEmpty)
    }

    @Test func whatIsRecognisedIsRemovedFromTheTitle() {
        let result = parse("on Friday at 2pm, Board review")
        #expect(result.draft.title == "Board review")
    }

    @Test func aDurationAloneChangesTheLength() {
        let result = parse("focus time for 2 hours")
        #expect(result.draft.end.timeIntervalSince(result.draft.start) == 7200)
    }

    @Test func aParsedDraftValidatesOnceTitled() throws {
        let event = try parse("Lunch tomorrow 12:30").draft.validated(calendar: calendar)
        #expect(event.title == "Lunch")
    }
}

@Suite("EventTextParser · Everyday phrasing")
struct EventTextParserEverydayTests {
    @Test func aThaiTimeWrittenWithADotAndNo() {
        let result = parse("ส่งรายงาน วันศุกร์ 17.00 น.")
        #expect(result.draft.title == "ส่งรายงาน")
        #expect(result.draft.start == at(1, 22, 17))
    }

    @Test func aThaiClockWithNoDoesNotSwallowTheWordThatFollows() {
        let result = parse("ประชุม 9:30 นักลงทุน")
        #expect(result.draft.start == at(1, 16, 9, 30))
        #expect(result.draft.title == "ประชุม นักลงทุน")
    }

    @Test func thisSaturdayAndAfternoonTwoLeaveOnlyTheTitle() {
        let result = parse("ทานข้าวกับแม่ เสาร์นี้ บ่าย 2")
        #expect(result.draft.title == "ทานข้าวกับแม่")
        #expect(result.draft.start == at(1, 16, 14))
    }

    @Test func aPartOfTheDayWithABareHour() {
        #expect(parse("ประชุม พรุ่งนี้ เช้า 9").draft.start == at(1, 16, 9))
        #expect(parse("ดินเนอร์ พรุ่งนี้ เย็น 6").draft.start == at(1, 16, 18))
    }

    @Test func monthFirstDatesWorkWhenTheyCannotBeDayFirst() {
        let american = parse("dentist 3/15 at 4pm")
        #expect(american.draft.start == at(3, 15, 16))
        #expect(american.draft.title == "dentist")
        // Both readings are possible: day/month wins.
        #expect(parse("dentist 3/4 at 4pm").draft.start == at(4, 3, 16))
    }
}

@Suite("EventTextParser · Buddhist calendar device")
struct BuddhistCalendarParserTests {
    /// A Thai device's `Calendar.current` is Buddhist: year components are 543 ahead of the Gregorian ones.
    private let buddhist: Calendar = {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = utc
        return calendar
    }()

    @Test func typedDatesLandInTheRightGregorianYear() {
        let parsed = EventTextParser.parse("dentist 15 March 2027 10:00", now: now, calendar: buddhist)
        #expect(parsed.draft.start == at(3, 15, 10))
        #expect(parsed.draft.title == "dentist")
    }

    @Test func aDateWithoutAYearIsThisOrNextGregorianYear() {
        // `now` is in January 2027; 5 March is still ahead, 5 January has passed and rolls to 2028.
        let ahead = EventTextParser.parse("lunch 5 March 12:00", now: now, calendar: buddhist)
        #expect(ahead.draft.start == at(3, 5, 12))
        let passed = EventTextParser.parse("lunch 5 January 12:00", now: now, calendar: buddhist)
        #expect(passed.draft.start == at(1, 5, 12, year: 2028))
    }

    @Test func buddhistEraYearsAreConvertedInEveryDateFormat() {
        for text in ["dentist 15/3/2570 10:00", "dentist 2570-03-15 10:00", "dentist 15 March 2570 10:00", "dentist March 15 2570 10:00"] {
            let parsed = EventTextParser.parse(text, now: now, calendar: buddhist)
            #expect(parsed.draft.start == at(3, 15, 10), Comment(rawValue: text))
        }
    }

    @Test func aThaiBuddhistEraYearIsConverted() {
        let parsed = EventTextParser.parse("ทันตแพทย์ 15 มีนาคม 2570 10:00", now: now, calendar: buddhist)
        #expect(parsed.draft.start == at(3, 15, 10))
    }
}

@Suite("EventTextParser · Thai")
struct EventTextParserThaiTests {
    @Test func tomorrowAtTenOClock() {
        let result = parse("ประชุมทีมพรุ่งนี้ 10 โมง")
        #expect(result.draft.title == "ประชุมทีม")
        #expect(result.draft.start == at(1, 16, 10))
    }

    @Test func afternoonWordsWithALocation() {
        let result = parse("นัดหมอพรุ่งนี้บ่ายสองโมงที่โรงพยาบาล")
        #expect(result.draft.title == "นัดหมอ")
        #expect(result.draft.start == at(1, 16, 14))
        #expect(result.draft.location == "โรงพยาบาล")
    }

    @Test func eveningOClock() {
        #expect(parse("กินข้าวพรุ่งนี้ 6 โมงเย็น").draft.start == at(1, 16, 18))
    }

    @Test func thumRoundsFromSevenPM() {
        let result = parse("กินข้าววันศุกร์ 2 ทุ่ม")
        #expect(result.draft.title == "กินข้าว")
        // Today is a Friday, so "วันศุกร์" is next week's.
        #expect(result.draft.start == at(1, 22, 20))
    }

    @Test func halfPastWithKhrueng() {
        #expect(parse("ประชุมพรุ่งนี้ 10 โมงครึ่ง").draft.start == at(1, 16, 10, 30))
    }

    @Test func tiIsAfterMidnight() {
        #expect(parse("ไปสนามบินพรุ่งนี้ตี 4").draft.start == at(1, 16, 4))
    }

    @Test func noonAndDuration() {
        let result = parse("ทานข้าวเที่ยงวันนี้ 2 ชั่วโมง")
        #expect(result.draft.start == at(1, 15, 12))
        #expect(result.draft.end == at(1, 15, 14))
    }

    @Test func dayAfterTomorrow() {
        #expect(parse("ส่งงานมะรืนนี้ 3 โมงเย็น").draft.start == at(1, 17, 15))
    }

    @Test func allDay() {
        let result = parse("ลาพักร้อนพรุ่งนี้ทั้งวัน")
        #expect(result.draft.isAllDay)
        #expect(result.draft.title == "ลาพักร้อน")
        #expect(result.draft.start == at(1, 16, 0))
    }

    @Test func aTitleThatEndsInADayWordIsLeftAloneWhenNothingWasRead() {
        #expect(parse("ไปตลาดวัน").draft.title == "ไปตลาดวัน")
        #expect(parse("ไปตลาดวัน").recognized.isEmpty)
    }

    @Test func thaiMonthNamesAreDates() {
        #expect(parse("ประชุมวันที่ 25 กุมภาพันธ์ 10 โมง").draft.start == at(2, 25, 10))
        #expect(parse("นัดหมอ 3 มี.ค. บ่ายสองโมง").draft.start == at(3, 3, 14))
        #expect(parse("ส่งรายงาน 9 ก.ย ทั้งวัน").draft.start == at(9, 9, 0))
    }

    @Test func aBuddhistEraYearIsConverted() {
        let result = parse("ประชุมใหญ่ 3 มีนาคม 2570 10 โมง")
        #expect(result.draft.title == "ประชุมใหญ่")
        #expect(result.draft.start == at(3, 3, 10))
    }

    @Test func aThaiDateWithoutAYearMeansTheNextOccurrence() {
        // 3 January has already passed in 2027, so it means 2028.
        #expect(parse("ขึ้นปีใหม่ 3 ม.ค. ทั้งวัน").draft.start == at(1, 3, 0, year: 2028))
    }

    @Test func everyDayRepeatsDaily() {
        let result = parse("ออกกำลังกายทุกวัน 6 โมงเย็น")
        #expect(result.draft.title == "ออกกำลังกาย")
        #expect(result.draft.repeatRule == .daily)
        #expect(result.draft.start == at(1, 15, 18))
    }

    @Test func everySpecificWeekdayRepeatsWeekly() {
        let result = parse("ประชุมทีมทุกวันจันทร์ 10 โมง")
        #expect(result.draft.title == "ประชุมทีม")
        #expect(result.draft.repeatRule == .weekly)
        #expect(result.draft.start == at(1, 18, 10))
    }
}

@Suite("EventTextParser · Robustness")
struct EventTextParserRobustnessTests {
    @Test func aHugeNumberDoesNotCrash() {
        for sentence in [
            "lunch in 99999999999999 weeks",
            "call in 999999999999999999999 days",
            "sync in 1e9 hours",
            "workshop for 99999999999 hours tomorrow 9am",
            "ประชุมอีก 99999999999999 วัน"
        ] {
            let result = parse(sentence)
            #expect(result.draft.end >= result.draft.start)
        }
    }

    @Test func aLongDurationIsCappedAtAMonth() {
        let result = parse("retreat tomorrow 9am for 99999 hours")
        #expect(result.draft.end.timeIntervalSince(result.draft.start) == 30 * 86_400)
    }

    @Test func daysAreCalendarDaysNotSeconds() {
        // 3 days from Friday 15th is Monday 18th whatever the clock does in between.
        #expect(parse("dentist in 3 days at 2pm").draft.start == at(1, 18, 14))
    }

    @Test func versionNumbersAndPricesStayInTheTitle() {
        let version = parse("Review v2.10 release tomorrow")
        #expect(version.draft.title == "Review v2.10 release")
        #expect(version.draft.start == at(1, 16, 9))

        let price = parse("Pay 5.50 rent")
        #expect(price.draft.title == "Pay 5.50 rent")
        #expect(price.recognized.isEmpty)
    }

    @Test func aDotTimeNeedsAnAnchorOrAMeridiem() {
        #expect(parse("meet at 5.30").draft.start == at(1, 15, 17, 30))
        #expect(parse("lunch 12.30pm").draft.start == at(1, 15, 12, 30))
        #expect(parse("standup 9:30 tomorrow").draft.start == at(1, 16, 9, 30))
        #expect(parse("นัดเวลา 10.30 พรุ่งนี้").draft.start == at(1, 16, 10, 30))
    }
}

@Suite("EventTextParser · Relative")
struct EventTextParserRelativeTests {
    @Test func inHoursIsFromNow() {
        let result = parse("call Anna in 2 hours")
        #expect(result.draft.title == "call Anna")
        #expect(result.draft.start == at(1, 15, 12, 20))
        // "in 2 hours" is when it starts, not how long it lasts.
        #expect(result.draft.end == at(1, 15, 13, 20))
        #expect(result.recognized == [.time])
    }

    @Test func minutesAreRoundedToFive() {
        #expect(parse("stretch in 25 minutes").draft.start == at(1, 15, 10, 45))
        #expect(parse("tea in half an hour").draft.start == at(1, 15, 10, 50))
    }

    @Test func inDaysKeepsAnExplicitTime() {
        let result = parse("dentist in 3 days at 2pm")
        #expect(result.draft.title == "dentist")
        #expect(result.draft.start == at(1, 18, 14))
    }

    @Test func inWeeksMeansThatDayAtNine() {
        #expect(parse("review in 2 weeks").draft.start == at(1, 29, 9))
    }

    @Test func partsOfTheDayStandInForAClockTime() {
        #expect(parse("workshop tomorrow morning").draft.start == at(1, 16, 9))
        #expect(parse("yoga this evening").draft.start == at(1, 15, 18))
        #expect(parse("gym in the afternoon").draft.start == at(1, 15, 14))
        #expect(parse("dinner tonight").draft.start == at(1, 15, 20))
    }

    @Test func aPartOfTheDayWordAloneIsJustTheTitle() {
        let result = parse("Morning standup")
        #expect(result.draft.title == "Morning standup")
        #expect(result.recognized.isEmpty)
    }

    @Test func aClockTimeBeatsAPartOfTheDay() {
        #expect(parse("workshop tomorrow morning 10:30").draft.start == at(1, 16, 10, 30))
    }

    @Test func thaiOffsetsAndPartsOfTheDay() {
        #expect(parse("ประชุมอีก 2 ชั่วโมง").draft.start == at(1, 15, 12, 20))
        #expect(parse("ประชุมอีก 2 ชั่วโมง").draft.title == "ประชุม")

        let morning = parse("พรุ่งนี้เช้า ไปตลาด")
        #expect(morning.draft.title == "ไปตลาด")
        #expect(morning.draft.start == at(1, 16, 9))

        let evening = parse("ทานข้าวเย็นนี้")
        #expect(evening.draft.title == "ทานข้าว")
        #expect(evening.draft.start == at(1, 15, 18))
    }
}

@Suite("EventTextParser · Repeat")
struct EventTextParserRepeatTests {
    @Test func everyWeekdayInEnglish() {
        let result = parse("standup every monday 9:30")
        #expect(result.draft.title == "standup")
        #expect(result.draft.repeatRule == .weekly)
        #expect(result.draft.start == at(1, 18, 9, 30))
        #expect(result.recognized.contains(.repeatRule))
    }

    @Test func dailyWeeklyMonthlyYearly() {
        #expect(parse("vitamins daily 8am").draft.repeatRule == .daily)
        #expect(parse("review every week friday").draft.repeatRule == .weekly)
        #expect(parse("rent every month 1/2 9am").draft.repeatRule == .monthly)
        #expect(parse("birthday yearly tomorrow all day").draft.repeatRule == .yearly)
    }

    @Test func everyOtherWeekIsBiweekly() {
        #expect(parse("1:1 every other week tomorrow 3pm").draft.repeatRule == .biweekly)
        #expect(parse("payday biweekly friday").draft.repeatRule == .biweekly)
    }

    @Test func repeatWordsAreRemovedFromTheTitle() {
        #expect(parse("gym every day 6pm").draft.title == "gym")
    }

    @Test func aSentenceWithoutRepeatWordsDoesNotRepeat() {
        let result = parse("lunch tomorrow 12:30")
        #expect(result.draft.repeatRule == .never)
        #expect(!result.recognized.contains(.repeatRule))
    }

    @Test func theRepeatChoiceReachesTheValidatedEvent() throws {
        let event = try parse("standup every monday 9:30").draft.validated(calendar: calendar)
        #expect(event.repeatRule == .weekly)
    }
}
