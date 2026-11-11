import Foundation
import Testing
@testable import PlanerCore

/// Belegte Zeit, freie Luecken und Ueberschneidungen.
@Suite("Stundenplan")
struct TimetableTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private func time(_ raw: String) -> ClockTime { ClockTime(raw)! }

    /// Montag, KW 41.
    private let monday = DateKey(year: 2026, month: 10, day: 5)

    private func course(_ title: String, _ from: String, _ to: String,
                        weekday: Int = 1) -> CourseItem {
        CourseItem(
            title: title, weekday: weekday,
            start: ClockTime(from)!, end: ClockTime(to)!,
            firstDay: DateKey(year: 2026, month: 10, day: 1),
            lastDay: DateKey(year: 2027, month: 3, day: 31)
        )
    }

    /// Ein Montag mit zwei Vorlesungen am Vormittag und einer Uebung am
    /// Nachmittag.
    private func state() -> DashboardState {
        DashboardState(courses: [
            course("Analysis", "08:15", "09:45"),
            course("Lineare Algebra", "10:15", "11:45"),
            course("Übung", "14:00", "15:30"),
        ])
    }

    // MARK: - Sitzungen des Tages

    @Test func listsTheDaysSessionsInOrder() {
        let sessions = state().courses(on: monday, today: monday)
        #expect(sessions.map(\.title) == ["Analysis", "Lineare Algebra", "Übung"])
        #expect(state().courses(on: monday.adding(days: 1), today: monday).isEmpty)
    }

    @Test func noLecturesOnPublicHolidays() {
        // 2026-10-05 ist ein gewoehnlicher Montag; der 2027-01-04 auch, aber
        // Heilige Drei Koenige faellt 2027 auf einen Mittwoch.
        var state = DashboardState(courses: [course("Analysis", "08:15", "09:45", weekday: 3)])
        state.courses[0].firstDay = day("2026-10-01")

        let epiphany = day("2027-01-06")
        #expect(Holidays.isHoliday(epiphany))
        #expect(state.courses[0].occurs(on: epiphany))
        // Der Rhythmus sagt ja, der Feiertag sagt nein.
        #expect(state.courses(on: epiphany, today: monday).isEmpty)
    }

    @Test func noLecturesWhileOnVacation() {
        var state = state()
        state.vacationRanges = [VacationRange(start: monday, end: monday.adding(days: 6))]
        #expect(state.courses(on: monday, today: monday).isEmpty)
        #expect(!state.courses(on: monday.adding(days: 7), today: monday).isEmpty)
    }

    // MARK: - Belegte Zeit

    @Test func busyBlocksCombineCoursesAndTimedEvents() {
        var state = state()
        state.events = [
            EventItem(title: "Zahnarzt", startDate: monday, time: "16:00", durationMinutes: 45),
            EventItem(title: "Einkaufen", startDate: monday),
        ]

        let blocks = state.busyBlocks(on: monday, today: monday)
        // Der Termin ohne Uhrzeit belegt nichts.
        #expect(blocks.count == 4)
        #expect(blocks.map(\.title) == ["Analysis", "Lineare Algebra", "Übung", "Zahnarzt"])
        #expect(blocks.filter(\.isCourse).count == 3)
        #expect(blocks.last?.span.text == "16:00–16:45")
    }

    @Test func eventWithoutDurationIsAssumedToTakeAnHour() {
        let event = EventItem(title: "Kaffee", startDate: monday, time: "16:00")
        #expect(event.span?.text == "16:00–17:00")
        #expect(EventItem(title: "Ganztags", startDate: monday).span == nil)
    }

    // MARK: - Freie Luecken

    @Test func findsTheGapsBetweenSessions() {
        let free = state().freeSlots(on: monday, today: monday)
        #expect(free.map(\.text) == [
            "09:45–10:15",   // zwischen den Vorlesungen
            "11:45–14:00",   // Mittag
            "15:30–20:00",   // der Rest des Tages
        ])
    }

    @Test func shortGapsAreNotWorthMentioning() {
        let state = DashboardState(courses: [
            course("Erste", "08:00", "09:45"),
            course("Zweite", "10:00", "11:30"),
        ])
        // Eine Viertelstunde ist der Weg zum Hoersaal, kein Zeitfenster.
        let free = state.freeSlots(on: monday, today: monday, minimumMinutes: 30)
        #expect(!free.contains { $0.text == "09:45–10:00" })
        #expect(free.first?.text == "11:30–20:00")
    }

    @Test func theWholeDayIsFreeWhenNothingIsPlanned() {
        let free = DashboardState().freeSlots(on: monday, today: monday)
        #expect(free.map(\.text) == ["08:00–20:00"])
    }

    @Test func earlyAndLateEntriesStretchTheDay() {
        var state = DashboardState(courses: [course("Früh", "07:00", "08:30")])
        state.events = [EventItem(title: "Spät", startDate: monday, time: "21:00",
                                  durationMinutes: 60)]

        let free = state.freeSlots(on: monday, today: monday)
        #expect(free.first?.text == "08:30–21:00")
        // Nach dem spaeten Termin bleibt nichts Nennenswertes mehr.
        #expect(free.count == 1)
    }

    @Test func overlappingBlocksDoNotProduceGhostGaps() {
        var state = DashboardState(courses: [course("Vorlesung", "10:00", "12:00")])
        state.events = [EventItem(title: "Termin", startDate: monday, time: "10:30",
                                  durationMinutes: 180)]

        let free = state.freeSlots(on: monday, today: monday)
        #expect(free.map(\.text) == ["08:00–10:00", "13:30–20:00"])
    }

    // MARK: - Ueberschneidungen

    @Test func conflictsNameWhatIsInTheWay() {
        let planned = TimeSpan(start: time("11:00"), minutes: 60)
        let clashes = state().conflicts(with: planned, on: monday, today: monday)

        #expect(clashes.count == 1)
        #expect(clashes[0].label == "Vorlesung Lineare Algebra")
        #expect(clashes[0].span.text == "10:15–11:45")
    }

    @Test func aFreeSlotHasNoConflicts() {
        let planned = TimeSpan(start: time("12:00"), minutes: 90)
        #expect(state().conflicts(with: planned, on: monday, today: monday).isEmpty)
    }

    @Test func anEntryDoesNotCollideWithItself() {
        var state = state()
        let event = EventItem(title: "Zahnarzt", startDate: monday, time: "16:00",
                              durationMinutes: 60)
        state.events = [event]

        let planned = TimeSpan(start: time("16:00"), minutes: 60)
        #expect(state.conflicts(with: planned, on: monday, today: monday).count == 1)
        #expect(state.conflicts(with: planned, on: monday, today: monday,
                                ignoring: event.id).isEmpty)
    }

    // MARK: - Kurse zaehlen nicht mit
    //
    // Der Kern der Trennung: Ein Stundenplan darf die Tagesbewertung nicht
    // anfassen. Sonst waere jeder Vorlesungstag ein Tag mit sechs offenen
    // Punkten, der Ring stuende auf null und die Serie waere weg.

    @Test func coursesDoNotCountTowardsTheDay() {
        let withCourses = state().stats(for: monday, today: monday)
        let withoutCourses = DashboardState().stats(for: monday, today: monday)

        #expect(withCourses.total == 0)
        #expect(withCourses.itemTotal == 0)
        #expect(withCourses.fraction == withoutCourses.fraction)
        // Ein reiner Unitag bleibt „leer" - und damit neutral fuer die Serie.
        #expect(withCourses.isEmpty)
        #expect(!withCourses.isPerfect)
    }

    @Test func coursesDoNotBreakTheStreak() {
        var state = state()
        let habit = HabitItem(title: "Lesen", startDate: monday.adding(days: -10))
        state.habits = [habit]
        for offset in 1...5 {
            state.completions.setDone(habit.id, on: monday.adding(days: -offset), true)
        }
        // Fuenf perfekte Tage - obwohl an jedem Montag Vorlesungen stehen.
        #expect(state.currentStreak(today: monday) == 5)
    }

    @Test func theAgendaKnowsItsSessions() {
        let agenda = state().agenda(for: monday, today: monday)
        #expect(agenda.courses.count == 3)
        #expect(agenda.busyBlocks.count == 3)
        #expect(!agenda.isEmpty)
    }

    // MARK: - Anordnung nebeneinander

    @Test func blocksWithoutOverlapShareOneLane() {
        let laid = TimetableLayout.lanes(for: state().busyBlocks(on: monday, today: monday))
        #expect(laid.count == 3)
        #expect(laid.allSatisfy { $0.lane == 0 && $0.laneCount == 1 })
        #expect(laid.allSatisfy { !$0.isConflicting })
    }

    @Test func collidingBlocksAreSetSideBySide() {
        var state = state()
        state.events = [EventItem(title: "Termin", startDate: monday, time: "10:30",
                                  durationMinutes: 60)]

        let laid = TimetableLayout.lanes(for: state.busyBlocks(on: monday, today: monday))
        let lecture = laid.first { $0.block.title == "Lineare Algebra" }
        let event = laid.first { $0.block.title == "Termin" }

        #expect(lecture?.lane == 0)
        #expect(event?.lane == 1)
        #expect(lecture?.laneCount == 2)
        #expect(event?.isConflicting == true)

        // Die uebrigen Bloecke bleiben breit: Eine Kollision am Vormittag darf
        // den Nachmittag nicht schmal machen.
        #expect(laid.first { $0.block.title == "Übung" }?.laneCount == 1)
    }

    @Test func threeAtOnceGetThreeLanes() {
        let blocks = [
            BusyBlock(course: course("A", "10:00", "12:00")),
            BusyBlock(course: course("B", "10:30", "11:30")),
            BusyBlock(course: course("C", "11:00", "12:30")),
        ]
        let laid = TimetableLayout.lanes(for: blocks)
        #expect(Set(laid.map(\.lane)) == [0, 1, 2])
        #expect(laid.allSatisfy { $0.laneCount == 3 })
    }

    @Test func touchingBlocksStayInOneLane() {
        let blocks = [
            BusyBlock(course: course("A", "08:15", "09:45")),
            BusyBlock(course: course("B", "09:45", "11:15")),
        ]
        let laid = TimetableLayout.lanes(for: blocks)
        #expect(laid.allSatisfy { $0.lane == 0 && $0.laneCount == 1 && !$0.isConflicting })
    }
}
