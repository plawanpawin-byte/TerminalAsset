import Foundation

/// What `EventTextParser` made of a sentence: a draft to review, and which parts it actually understood.
public struct ParsedEvent: Sendable, Equatable {
    public enum Recognized: Sendable, Hashable {
        case date, time, duration, location, allDay
    }

    public var draft: NewEventDraft
    public let recognized: Set<Recognized>
}

/// Turns a sentence like "lunch with Anna tomorrow 12:30" or "ประชุมทีมพรุ่งนี้ 10 โมง" into an event draft.
///
/// Deterministic and on-device: no network, no model. It only ever produces a *draft*; the user reviews it in the
/// New Event form before anything is written to the calendar. Anything it cannot read stays in the title.
public enum EventTextParser {
    public static func parse(_ input: String, now: Date, calendar: Calendar) -> ParsedEvent {
        var scanner = TextScanner(text: input)
        var recognized: Set<ParsedEvent.Recognized> = []
        let today = calendar.startOfDay(for: now)

        // Words that decide whether a bare hour means morning or evening.
        let evening = matches(input, "tonight|evening|night|dinner|เย็น|ค่ำ|คืนนี้")
        var day: Date?
        var allDay = false

        // MARK: All-day
        if scanner.take("\\ball[- ]?day\\b|ทั้งวัน") != nil {
            allDay = true
            recognized.insert(.allDay)
        }

        // MARK: Dates
        if let g = scanner.take("(\\d{4})-(\\d{1,2})-(\\d{1,2})", where: { g in
            date(year: int(g[1]), month: int(g[2]), day: int(g[3]), today: today, calendar: calendar) != nil
        }) {
            day = date(year: int(g[1]), month: int(g[2]), day: int(g[3]), today: today, calendar: calendar)
        } else if let g = scanner.take("(?:^|\\s)(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?(?![\\d:/])", where: { g in
            date(year: year(g[3]), month: int(g[2]), day: int(g[1]), today: today, calendar: calendar) != nil
        }) {
            day = date(year: year(g[3]), month: int(g[2]), day: int(g[1]), today: today, calendar: calendar)
        } else if let g = scanner.take("(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthNames))\\b(?:\\s+(\\d{4}))?", where: { g in
            date(year: int(g[3]), month: month(g[2]), day: int(g[1]), today: today, calendar: calendar) != nil
        }) {
            day = date(year: int(g[3]), month: month(g[2]), day: int(g[1]), today: today, calendar: calendar)
        } else if let g = scanner.take("\\b(\(monthNames))\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4}))?", where: { g in
            date(year: int(g[3]), month: month(g[1]), day: int(g[2]), today: today, calendar: calendar) != nil
        }) {
            day = date(year: int(g[3]), month: month(g[1]), day: int(g[2]), today: today, calendar: calendar)
        } else if let g = scanner.take("(?:\\bon\\s+)?\\b(day after tomorrow)\\b|มะรืน(?:นี้)?") {
            _ = g
            day = calendar.date(byAdding: .day, value: 2, to: today)
        } else if scanner.take("(?:\\bon\\s+)?\\b(?:tomorrow|tmr|tmrw)\\b|พรุ่งนี้") != nil {
            day = calendar.date(byAdding: .day, value: 1, to: today)
        } else if scanner.take("(?:\\bon\\s+)?\\b(?:today|tonight)\\b|วันนี้|คืนนี้") != nil {
            day = today
        } else if let g = scanner.take(
            "(?:\\b(next|this)\\s+)?\\b(\(englishWeekdays))\\b(?:\\s*หน้า)?|(?:วัน)?(\(thaiWeekdays))(?:\\s*(หน้า))?"
        ) {
            let name = g[2] ?? g[3] ?? ""
            let next = g[1]?.lowercased() == "next" || g[4] != nil
            let including = g[1]?.lowercased() == "this"
            if let weekday = weekday(named: name) {
                day = date(forWeekday: weekday, from: today, next: next, includingToday: including, calendar: calendar)
            }
        }
        if day != nil { recognized.insert(.date) }

        // MARK: Duration
        var duration: TimeInterval?
        if scanner.take("ครึ่งชั่วโมง|\\bhalf an? hour\\b") != nil {
            duration = 1800
        } else if let g = scanner.take("(\\d+(?:\\.\\d+)?)\\s*ชั่วโมง") {
            duration = double(g[1]).map { $0 * 3600 }
        } else if let g = scanner.take("(\\d+)\\s*นาที") {
            duration = double(g[1]).map { $0 * 60 }
        } else if let g = scanner.take("(?:\\bfor\\s+)?\\b(\\d+(?:\\.\\d+)?|an?)\\s*(hours?|hrs?|minutes?|mins?)\\b") {
            let amount = g[1]?.lowercased().hasPrefix("a") == true ? 1 : (double(g[1]) ?? 0)
            let unit = g[2]?.lowercased() ?? ""
            duration = unit.hasPrefix("h") ? amount * 3600 : amount * 60
        }
        if let value = duration, value <= 0 { duration = nil }
        if duration != nil { recognized.insert(.duration) }

        // MARK: Time of day (minutes since midnight)
        var startMinutes: Int?
        var endMinutes: Int?

        if let g = scanner.take(
            "(?:\\b(at|@|from|between)\\s*|(เวลา|ตอน|ตั้งแต่)\\s*)?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm)?\\s*(?:-|–|—|\\bto\\b|\\buntil\\b|\\btill\\b|\\band\\b|ถึง)\\s*(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm)?(?![\\d:])",
            where: { g in
                let anchored = g[1] != nil || g[2] != nil
                let marked = g[4] != nil || g[5] != nil || g[7] != nil || g[8] != nil
                return (anchored || marked)
                    && clock(hour: g[3], minute: g[4], marker: g[5] ?? g[8], evening: evening) != nil
                    && clock(hour: g[6], minute: g[7], marker: g[8] ?? g[5], evening: evening) != nil
            }
        ) {
            startMinutes = clock(hour: g[3], minute: g[4], marker: g[5] ?? g[8], evening: evening)
            endMinutes = clock(hour: g[6], minute: g[7], marker: g[8] ?? g[5], evening: evening)
        } else if let g = scanner.take(
            "(?:เวลา|ตอน)?\\s*(บ่าย|เย็น|ค่ำ|เช้า)?\\s*(\(thaiNumber))?\\s*โมง\\s*(เช้า|เย็น|ครึ่ง)?",
            where: { g in thaiOClock(prefix: g[1], number: g[2], suffix: g[3]) != nil }
        ) {
            startMinutes = thaiOClock(prefix: g[1], number: g[2], suffix: g[3])
        } else if let g = scanner.take(
            "(\(thaiNumber))?\\s*ทุ่ม\\s*(ครึ่ง)?",
            where: { g in (1...5).contains(thaiInt(g[1]) ?? 1) }
        ) {
            startMinutes = (18 + (thaiInt(g[1]) ?? 1)) * 60 + (g[2] != nil ? 30 : 0)
        } else if let g = scanner.take("ตี\\s*(\(thaiNumber))", where: { g in (1...6).contains(thaiInt(g[1]) ?? 0) }) {
            startMinutes = (thaiInt(g[1]) ?? 0) * 60
        } else if scanner.take("เที่ยง(?!คืน)|\\b(?:noon|midday)\\b") != nil {
            startMinutes = 12 * 60
        } else if let g = scanner.take(
            "(?:\\b(?:at|@)\\s*|(?:เวลา|ตอน)\\s*)?(\\d{1,2})[:.](\\d{2})\\s*(am|pm)?(?![\\d:])",
            where: { g in clock(hour: g[1], minute: g[2], marker: g[3], evening: evening) != nil }
        ) {
            startMinutes = clock(hour: g[1], minute: g[2], marker: g[3], evening: evening)
        } else if let g = scanner.take(
            "(?:\\b(?:at|@)\\s*|(?:เวลา|ตอน)\\s*)?(\\d{1,2})\\s*(am|pm)\\b",
            where: { g in clock(hour: g[1], minute: nil, marker: g[2], evening: evening) != nil }
        ) {
            startMinutes = clock(hour: g[1], minute: nil, marker: g[2], evening: evening)
        } else if let g = scanner.take(
            "(?:\\b(?:at|@)\\s*|(?:เวลา|ตอน)\\s*)(\\d{1,2})(?![\\d:.])",
            where: { g in clock(hour: g[1], minute: nil, marker: nil, evening: evening) != nil }
        ) {
            startMinutes = clock(hour: g[1], minute: nil, marker: nil, evening: evening)
        }
        if startMinutes != nil { recognized.insert(.time) }

        // MARK: Location
        var location = ""
        if let g = scanner.take("(?:\\bat\\b|@|ที่)\\s*(.+)$") {
            location = (g[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !location.isEmpty { recognized.insert(.location) }
        }

        // MARK: Assemble
        var draft = NewEventDraft.starting(on: now, now: now, calendar: calendar)
        draft.title = scanner.cleanedTitle(trimThaiConnectors: recognized.contains { $0 != .location })
        draft.location = location
        draft.isAllDay = allDay

        if allDay {
            let start = day ?? today
            draft.start = start
            draft.end = start
        } else if let startMinutes {
            var start = atMinutes(startMinutes, on: day ?? today, calendar: calendar)
            // A time with no date means the next time that clock reading comes round.
            if day == nil, start <= now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) {
                start = tomorrow
            }
            draft.start = start
            if let endMinutes {
                var end = atMinutes(endMinutes, on: calendar.startOfDay(for: start), calendar: calendar)
                if end <= start, let later = calendar.date(byAdding: .day, value: 1, to: end) { end = later }
                draft.end = end
            } else {
                draft.end = start.addingTimeInterval(duration ?? NewEventDraft.defaultDuration)
            }
        } else if let day {
            draft.start = NewEventDraft.starting(on: day, now: now, calendar: calendar).start
            draft.end = draft.start.addingTimeInterval(duration ?? NewEventDraft.defaultDuration)
        } else if let duration {
            draft.end = draft.start.addingTimeInterval(duration)
        }

        return ParsedEvent(draft: draft, recognized: recognized)
    }

    // MARK: - Vocabulary

    private static let monthNames =
        "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"
    private static let englishWeekdays =
        "monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun"
    /// "อาทิตย์" alone also means "week", so Sunday needs its "วัน".
    private static let thaiWeekdays = "จันทร์|อังคาร|พุธ|พฤหัสบดี|พฤหัส|ศุกร์|เสาร์|วันอาทิตย์"
    private static let thaiNumber = "\\d{1,2}|สิบเอ็ด|สิบสอง|สิบ|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า"

    private static func month(_ name: String?) -> Int? {
        guard let prefix = name?.lowercased().prefix(3) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return months.firstIndex(of: String(prefix)).map { $0 + 1 }
    }

    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    private static func weekday(named name: String) -> Int? {
        let lowered = name.lowercased()
        if lowered.contains("อาทิตย์") { return 1 }
        if lowered.contains("จันทร์") { return 2 }
        if lowered.contains("อังคาร") { return 3 }
        if lowered.contains("พุธ") { return 4 }
        if lowered.contains("พฤหัส") { return 5 }
        if lowered.contains("ศุกร์") { return 6 }
        if lowered.contains("เสาร์") { return 7 }
        switch lowered.prefix(3) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return nil
        }
    }

    // MARK: - Dates

    /// `year == nil` means "this year, or next year if that date has already passed".
    private static func date(year: Int?, month: Int?, day: Int?, today: Date, calendar: Calendar) -> Date? {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let currentYear = calendar.component(.year, from: today)
        let resolvedYear = year ?? currentYear
        guard let date = calendar.date(from: DateComponents(year: resolvedYear, month: month, day: day)),
              calendar.component(.day, from: date) == day
        else { return nil }
        if year == nil, date < today {
            return calendar.date(from: DateComponents(year: currentYear + 1, month: month, day: day))
                .flatMap { calendar.component(.day, from: $0) == day ? $0 : nil }
        }
        return date
    }

    private static func date(
        forWeekday weekday: Int,
        from today: Date,
        next: Bool,
        includingToday: Bool,
        calendar: Calendar
    ) -> Date? {
        var first = 1
        if next {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let offset = calendar.dateComponents([.day], from: today, to: nextWeek).day ?? 7
            first = offset
        } else if includingToday {
            first = 0
        }
        for offset in first..<(first + 7) {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return nil
    }

    private static func atMinutes(_ minutes: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day)) ?? day
    }

    // MARK: - Clock times

    /// Minutes since midnight for "3", "3:30", "3pm". A bare hour with no am/pm is read the way people mean it:
    /// 1–6 → afternoon, 7–11 → morning, unless the sentence says evening.
    private static func clock(hour: String?, minute: String?, marker: String?, evening: Bool) -> Int? {
        guard let hour = int(hour), (0...23).contains(hour) else { return nil }
        let minutes = int(minute) ?? 0
        guard (0...59).contains(minutes) else { return nil }

        var resolved = hour
        switch marker?.lowercased() {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            resolved = hour == 12 ? 0 : hour
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            resolved = hour == 12 ? 12 : hour + 12
        default:
            if hour >= 1 && hour <= 6 {
                resolved = hour + 12
            } else if evening && hour >= 7 && hour <= 11 {
                resolved = hour + 12
            }
        }
        return resolved * 60 + minutes
    }

    /// Thai "X โมง": 7–11 → morning, 1–6 → afternoon/evening, with บ่าย / เย็น / เช้า / ครึ่ง qualifiers.
    private static func thaiOClock(prefix: String?, number: String?, suffix: String?) -> Int? {
        let n = thaiInt(number) ?? (prefix == "บ่าย" ? 1 : nil)
        guard let n, (1...12).contains(n) else { return nil }
        let afternoon = prefix == "บ่าย" || prefix == "เย็น" || prefix == "ค่ำ" || suffix == "เย็น"
        let morning = prefix == "เช้า" || suffix == "เช้า"
        let hour: Int
        if afternoon {
            hour = n < 12 ? n + 12 : n
        } else if morning {
            hour = n
        } else {
            hour = (1...6).contains(n) ? n + 12 : n
        }
        return hour * 60 + (suffix == "ครึ่ง" ? 30 : 0)
    }

    private static func thaiInt(_ text: String?) -> Int? {
        guard let text else { return nil }
        if let value = Int(text) { return value }
        let words = [
            "หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6,
            "เจ็ด": 7, "แปด": 8, "เก้า": 9, "สิบ": 10, "สิบเอ็ด": 11, "สิบสอง": 12
        ]
        return words[text]
    }

    // MARK: - Small helpers

    private static func int(_ text: String?) -> Int? { text.flatMap { Int($0) } }
    private static func double(_ text: String?) -> Double? { text.flatMap { Double($0) } }

    /// Two-digit years mean 20xx. A missing year stays nil so the date logic can pick the coming one.
    private static func year(_ text: String?) -> Int? {
        guard let value = int(text) else { return nil }
        return value < 100 ? 2000 + value : value
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? Regex(pattern).ignoresCase() else { return false }
        return text.firstMatch(of: regex) != nil
    }

    /// The text still to be read. Each `take` blanks out what it recognised, so what is left is the title.
    private struct TextScanner {
        var text: String

        /// Removes the first match whose captures pass `accept`. Group 0 is the whole match.
        mutating func take(_ pattern: String, where accept: ([String?]) -> Bool = { _ in true }) -> [String?]? {
            guard let regex = try? Regex(pattern).ignoresCase() else { return nil }
            for match in text.matches(of: regex) {
                let groups = (0..<match.output.count).map { match.output[$0].substring.map(String.init) }
                guard accept(groups) else { continue }
                text.replaceSubrange(match.range, with: " ")
                return groups
            }
            return nil
        }

        /// Collapses spaces and trims words that only connected the removed parts ("on", "at", "for", "วัน" …).
        /// Thai connectors are glued to the word before them, so they are only cut when something was removed:
        /// otherwise a title that genuinely ends in "วัน" would lose it.
        func cleanedTitle(trimThaiConnectors: Bool) -> String {
            let connectors: Set<String> = [
                "on", "at", "for", "from", "until", "till", "to", "by", "in", "and", "@",
                "-", "–", "—", ",", ";", ":", "ที่", "เวลา", "ตอน", "วัน", "ใน", "ตั้งแต่"
            ]
            var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            while let first = words.first, connectors.contains(first.lowercased()) { words.removeFirst() }
            while let last = words.last, connectors.contains(last.lowercased()) { words.removeLast() }
            var title = words.joined(separator: " ")
            if trimThaiConnectors {
                for suffix in ["เวลา", "ตอน", "วัน", "ใน", "ตั้งแต่"] where title.hasSuffix(suffix) && title != suffix {
                    title.removeLast(suffix.count)
                    break
                }
            }
            return title.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
        }
    }
}
