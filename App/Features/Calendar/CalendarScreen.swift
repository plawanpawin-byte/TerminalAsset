import SwiftUI
import TerminalAssetDomain

/// Full calendar, opened from the tile on Today: a month grid with the selected day's agenda underneath,
/// or a day view with an hour grid. Events open the same detail screen as everywhere else.
struct CalendarScreen: View {
    private let today: TodayViewModel
    @State private var model: CalendarViewModel
    /// Set while the New Event form is open. Held here so the form keeps its state while the screen redraws.
    @State private var adding: AddEventViewModel?

    init(today: TodayViewModel, mode: CalendarViewModel.Mode) {
        self.today = today
        _model = State(initialValue: today.makeCalendarModel(mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $model.mode) {
                ForEach(CalendarViewModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            switch model.mode {
            case .month: MonthPane(model: model)
            case .day: DayPane(model: model)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await model.goToToday() }
                } label: {
                    Label("Go to today", systemImage: "calendar.circle")
                }
                Button {
                    presentAddEvent()
                } label: {
                    Label("Add event", systemImage: "plus")
                }
            }
        }
        .sheet(item: $adding) { form in
            AddEventView(model: form)
        }
        // A sync (or an edit made elsewhere in the app) can change events while this screen is open.
        .onChange(of: today.events) { Task { await model.refreshStored() } }
        .task {
            await model.onAppear()
            #if DEBUG
            await runLaunchAddEvent()
            #endif
        }
    }

    /// The month or day is already shown in the screen itself, so the bar only names the screen.
    private var title: String { String(localized: "Calendar") }

    @discardableResult
    private func presentAddEvent() -> AddEventViewModel {
        let calendarModel = model
        let form = today.makeAddEventModel(day: calendarModel.selectedDay) { start in
            await calendarModel.eventAdded(on: start)
        }
        adding = form
        return form
    }

    #if DEBUG
    /// `-addEvent form|submit`: lets CI screenshot the form, or the calendar after an event was added, without taps.
    private func runLaunchAddEvent() async {
        guard let mode = LaunchOptions.addEvent else { return }
        let form = presentAddEvent()
        await form.loadCalendars()
        if mode == "quick" || mode == "quickth" {
            form.quickText = mode == "quick"
                ? "Lunch with Anna tomorrow 12:30 at Cafe Amazon"
                : "ประชุมทีมพรุ่งนี้ 10 โมง ที่ห้องประชุม 2"
            form.applyQuickText()
            return
        }
        form.draft.title = "Dentist appointment"
        form.draft.location = "Bangkok Hospital"
        guard mode == "submit" else { return }
        if await form.save() { adding = nil }
    }
    #endif
}

// MARK: - Month

private struct MonthPane: View {
    let model: CalendarViewModel

    var body: some View {
        // Re-evaluated every minute so "today" moves at midnight.
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                // The grid has fixed-size cells, so like Apple Calendar it stops growing at a large size; the
                // agenda below it keeps scaling all the way up.
                VStack(spacing: 0) {
                    monthBar
                    weekdayRow
                    grid(today: context.date)
                        .gesture(swipe)
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Divider().padding(.top, 8)
                AgendaList(model: model)
            }
        }
    }

    private var monthBar: some View {
        HStack {
            Button {
                Task { await model.shiftMonth(-1) }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(model.displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                Task { await model.shiftMonth(1) }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 8)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private func grid(today: Date) -> some View {
        let counts = model.eventCounts
        return Grid(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(Array(model.weeks(today: today).enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(week) { day in
                        DayCell(
                            day: day,
                            isSelected: day.date == model.selectedDay,
                            eventCount: counts[day.date] ?? 0
                        ) {
                            Task { await model.select(day.date) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            Task { await model.shiftMonth(value.translation.width < 0 ? 1 : -1) }
        }
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let eventCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.body.weight(day.isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .frame(width: 36, height: 36)
                    .background { marker }

                HStack(spacing: 3) {
                    ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(day.isInDisplayedMonth ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(eventCount == 0 ? String(localized: "No events") : String(localized: "\(eventCount) events"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var numberColor: Color {
        if day.isToday { return .white }
        if isSelected { return .accentColor }
        return day.isInDisplayedMonth ? .primary : Color(.tertiaryLabel)
    }

    @ViewBuilder
    private var marker: some View {
        if day.isToday {
            Circle().fill(Color.accentColor)
        } else if isSelected {
            Circle().fill(Color.accentColor.opacity(0.14))
        }
    }
}

private struct AgendaList: View {
    let model: CalendarViewModel

    var body: some View {
        let events = model.agenda
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if events.isEmpty {
                    Text("No events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                } else {
                    ForEach(events) { event in
                        AgendaRow(event: event, day: model.selectedDay)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

private struct AgendaRow: View {
    let event: TimelineEvent
    let day: Date

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: event.key) {
            Group {
                if typeSize.isAccessibilitySize {
                    stacked
                } else {
                    sideBySide
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Time on the left, event on the right.
    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All day").font(.caption.weight(.semibold))
                } else {
                    Text(event.startDate, format: .dateTime.hour().minute())
                        .font(.subheadline.monospacedDigit())
                    Text(event.endDate, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 84, alignment: .trailing)

            bar
            details
            Spacer(minLength: 0)
            chevron
        }
    }

    /// At accessibility sizes a fixed time column would squeeze the title, so the time goes on top instead.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TimeText.range(of: event))
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                bar
                details
                Spacer(minLength: 0)
                chevron
            }
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.leading)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ContextChips(summary: event.summary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

// MARK: - Day

private struct DayPane: View {
    let model: CalendarViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Task { await model.shiftDay(-1) }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 36)
                }
                .accessibilityLabel("Previous day")
                Spacer()
                Text(model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.shiftDay(1) }
                } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 36)
                }
                .accessibilityLabel("Next day")
            }
            .padding(.horizontal, 8)

            if !model.allDayEvents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.allDayEvents) { event in
                            NavigationLink(value: event.key) {
                                Label(event.title, systemImage: "sun.max")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 6)
            }

            Divider()
            DayTimeline(day: model.selectedDay, positioned: model.positionedEvents, calendar: model.calendar)
                .gesture(
                    DragGesture(minimumDistance: 50).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        Task { await model.shiftDay(value.translation.width < 0 ? 1 : -1) }
                    }
                )
        }
    }
}

private struct DayTimeline: View {
    let day: Date
    let positioned: [PositionedEvent]
    let calendar: Calendar

    private let hourHeight: CGFloat = 60
    private let labelWidth: CGFloat = 56

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    eventsLayer
                    nowMarker
                }
                .frame(height: hourHeight * 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onAppear {
                let target = calendar.isDateInToday(day) ? calendar.component(.hour, from: Date()) - 1 : 7
                proxy.scrollTo(min(max(target, 0), 23), anchor: .top)
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(label(for: hour))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .accessibilityHidden(true)
    }

    private var eventsLayer: some View {
        GeometryReader { proxy in
            let left = labelWidth + 8
            let available = max(0, proxy.size.width - left - 8)
            ForEach(positioned) { item in
                let width = available / CGFloat(item.columnCount)
                let top = CGFloat(item.startMinute) / 60 * hourHeight
                let height = max(26, CGFloat(item.endMinute - item.startMinute) / 60 * hourHeight - 2)
                NavigationLink(value: item.event.key) {
                    EventBlock(event: item.event, height: height)
                }
                .buttonStyle(.plain)
                .frame(width: max(0, width - 3), height: height)
                .offset(x: left + width * CGFloat(item.column), y: top + 1)
            }
        }
    }

    @ViewBuilder
    private var nowMarker: some View {
        if calendar.isDateInToday(day) {
            TimelineView(.everyMinute) { context in
                let minutes = context.date.timeIntervalSince(calendar.startOfDay(for: context.date)) / 60
                HStack(spacing: 0) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Rectangle().fill(Color.red).frame(height: 1)
                }
                .padding(.leading, labelWidth)
                .offset(y: CGFloat(minutes) / 60 * hourHeight - 4)
                .accessibilityHidden(true)
            }
        }
    }

    private func label(for hour: Int) -> String {
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return "" }
        return hour == 0 ? "" : date.formatted(.dateTime.hour())
    }
}

private struct EventBlock: View {
    let event: TimelineEvent
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(height > 44 ? 2 : 1)
                if height > 40 {
                    Text(TimeText.range(of: event))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opaque base so the hour lines behind an event never cut through its text.
        .background {
            ZStack {
                Color(.systemBackground)
                Color.accentColor.opacity(0.16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
