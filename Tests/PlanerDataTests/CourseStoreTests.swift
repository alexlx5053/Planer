import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Kurse im Bestand: anlegen, aendern, ausfallen lassen, loeschen.
@Suite("Kurse im Bestand")
@MainActor
struct CourseStoreTests {

    /// Montag, KW 41.
    private let today = DateKey(year: 2026, month: 10, day: 5)

    private func store() -> StateStore {
        StateStore(inMemory: DashboardState(), today: today)
    }

    private func course(_ title: String = "Analysis", _ from: String = "08:15",
                        _ to: String = "09:45", weekday: Int = 1) -> CourseItem {
        CourseItem(
            title: title, weekday: weekday,
            start: ClockTime(from)!, end: ClockTime(to)!, room: "H 12",
            firstDay: DateKey(year: 2026, month: 10, day: 1),
            lastDay: DateKey(year: 2027, month: 3, day: 31)
        )
    }

    // MARK: - Anlegen

    @Test func addedCourseAppearsOnItsDay() {
        let store = store()
        #expect(!store.hasCourses)

        store.add(course: course())

        #expect(store.hasCourses)
        #expect(store.courses(on: today).map(\.title) == ["Analysis"])
        #expect(store.courses(on: today.adding(days: 1)).isEmpty)
        // Und naechste Woche wieder.
        #expect(store.courses(on: today.adding(days: 7)).count == 1)
    }

    /// Derselbe Fall, der bei Gewohnheiten dreimal zugeschlagen hat: Der
    /// Zwischenspeicher muss den neuen Eintrag sofort kennen.
    @Test func cacheDoesNotHideANewCourse() {
        let store = store()
        _ = store.agenda(for: today)

        store.add(course: course())

        #expect(store.agenda(for: today).courses.count == 1)
        #expect(store.busyBlocks(on: today).count == 1)
    }

    @Test func editingACourseTakesEffectEverywhere() {
        let store = store()
        store.add(course: course())
        _ = store.agenda(for: today)

        var changed = store.state.courses[0]
        changed.start = ClockTime(hour: 12)
        changed.end = ClockTime(hour: 14)
        store.update(course: changed)

        #expect(store.courses(on: today)[0].span.text == "12:00–14:00")
        #expect(store.freeSlots(on: today).map(\.text) == ["08:00–12:00", "14:00–20:00"])
    }

    // MARK: - Ausfall

    @Test func cancelledSessionAffectsOnlyThatDay() {
        let store = store()
        store.add(course: course())
        let item = store.state.courses[0]

        store.cancelSession(courseID: item.id, on: today)

        #expect(store.courses(on: today).isEmpty)
        #expect(store.courses(on: today.adding(days: 7)).count == 1)

        store.restoreSession(courseID: item.id, on: today)
        #expect(store.courses(on: today).count == 1)
    }

    // MARK: - Loeschen

    @Test func deletedCourseCanComeBack() {
        let store = store()
        store.add(course: course("Analysis"))
        store.add(course: course("Statistik", weekday: 2))

        let deleted = store.delete(courseID: store.state.courses[0].id)

        #expect(store.state.courses.map(\.title) == ["Statistik"])
        #expect(deleted?.descriptionOfKind == "Kurs")

        store.restore(deleted!)
        // An seiner alten Stelle, nicht hinten angehaengt.
        #expect(store.state.courses.map(\.title) == ["Analysis", "Statistik"])
    }

    // MARK: - Freie Zeit und Konflikte

    @Test func freeSlotsAccountForCoursesAndEvents() {
        let store = store()
        store.add(course: course("Analysis", "08:15", "09:45"))
        store.add(course: course("Lineare Algebra", "10:15", "11:45"))
        store.add(event: EventItem(title: "Zahnarzt", startDate: today, time: "14:00",
                                   durationMinutes: 60))

        #expect(store.freeSlots(on: today).map(\.text) == [
            "09:45–10:15", "11:45–14:00", "15:00–20:00",
        ])
    }

    @Test func conflictsAreReportedForThePlannedTime() {
        let store = store()
        store.add(course: course("Analysis", "08:15", "09:45"))

        let planned = TimeSpan(start: ClockTime(hour: 9), minutes: 60)
        let clashes = store.conflicts(with: planned, on: today)

        #expect(clashes.count == 1)
        #expect(clashes[0].title == "Analysis")
        #expect(store.conflicts(with: TimeSpan(start: ClockTime(hour: 16), minutes: 60),
                                on: today).isEmpty)
    }

    // MARK: - Semestervorgabe

    @Test func aNewCourseInheritsTheSemesterOfTheLastOne() {
        let store = store()
        var first = course()
        first.firstDay = DateKey(year: 2026, month: 10, day: 12)
        first.lastDay = DateKey(year: 2027, month: 2, day: 5)
        store.add(course: first)

        let inherited = store.semesterForNewCourse
        #expect(inherited.firstDay == first.firstDay)
        #expect(inherited.lastDay == first.lastDay)
    }

    // MARK: - Trennung von der Tagesplanung

    @Test func coursesChangeNeitherRingNorStreak() {
        let store = store()
        let before = store.stats(for: today)

        store.add(course: course())

        let after = store.stats(for: today)
        #expect(after.itemTotal == before.itemTotal)
        #expect(after.fraction == before.fraction)
        #expect(store.streak == 0)
    }

    // MARK: - Datei

    @Test func coursesSurviveSavingAndLoading() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("planer-kurse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let location = StoreLocation(directory: directory)
        let store = StateStore(location: location, today: today)
        store.add(course: course("Analysis"))
        store.flush()

        let reloaded = StateStore(location: location, today: today)
        #expect(reloaded.state.courses.map(\.title) == ["Analysis"])
        #expect(reloaded.courses(on: today)[0].room == "H 12")
    }
}
