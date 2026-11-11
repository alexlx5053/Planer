import Foundation
import Testing
@testable import PlanerCore

/// Uhrzeit und Zeitspanne - die Grundlage des Stundenplans.
@Suite("Uhrzeit")
struct ClockTests {

    private func time(_ raw: String) -> ClockTime { ClockTime(raw)! }

    // MARK: - Lesen und Schreiben

    @Test func parsesAndFormats() {
        #expect(time("08:15").minutes == 8 * 60 + 15)
        #expect(time("00:00").minutes == 0)
        #expect(time("23:59").text == "23:59")
        #expect(ClockTime(hour: 9).text == "09:00")
    }

    @Test func rejectsNonsense() {
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime("8:1:2") == nil)
        #expect(ClockTime("acht") == nil)
        #expect(ClockTime("08:60") == nil)
        #expect(ClockTime("") == nil)
    }

    @Test func staysWithinTheDay() {
        #expect(ClockTime(minutes: -30).minutes == 0)
        #expect(ClockTime(minutes: 5000).text == "23:59")
        #expect(time("23:30").adding(minutes: 120).text == "23:59")
    }

    @Test func shortFormDropsEmptyMinutes() {
        #expect(ClockTime(hour: 8).shortText == "8")
        #expect(time("08:15").shortText == "8:15")
    }

    @Test func roundsToFullHours() {
        #expect(time("08:15").flooredToHour.text == "08:00")
        #expect(time("08:15").ceiledToHour.text == "09:00")
        // Liegt sie schon auf der Stunde, bleibt sie dort - sonst waechse das
        // Zeitfenster bei jedem Aufruf um eine Stunde.
        #expect(time("09:00").ceiledToHour.text == "09:00")
    }

    @Test func survivesTheFile() throws {
        let raw = try JSONEncoder().encode([time("08:15")])
        #expect(String(data: raw, encoding: .utf8) == "[\"08:15\"]")
        #expect(try JSONDecoder().decode([ClockTime].self, from: raw) == [time("08:15")])
    }

    // MARK: - Zeitspanne

    @Test func touchingSpansDoNotOverlap() {
        let first = TimeSpan(start: time("08:15"), end: time("09:45"))
        let second = TimeSpan(start: time("09:45"), end: time("11:15"))
        // Der wichtigste Fall ueberhaupt: Ein Doppelblock darf keinen Konflikt
        // melden.
        #expect(!first.overlaps(second))
        #expect(!second.overlaps(first))
    }

    @Test func realOverlapIsFound() {
        let lecture = TimeSpan(start: time("10:15"), end: time("11:45"))
        #expect(lecture.overlaps(TimeSpan(start: time("11:00"), minutes: 60)))
        #expect(lecture.overlaps(TimeSpan(start: time("09:00"), minutes: 180)))
        #expect(lecture.overlaps(TimeSpan(start: time("10:30"), minutes: 15)))
        #expect(!lecture.overlaps(TimeSpan(start: time("12:00"), minutes: 60)))
    }

    @Test func endNeverPrecedesStart() {
        let span = TimeSpan(start: time("14:00"), end: time("09:00"))
        #expect(span.end == span.start)
        #expect(span.minutes == 0)
    }

    @Test func mergingJoinsOverlappingAndTouching() {
        let spans = [
            TimeSpan(start: time("10:00"), end: time("11:00")),
            TimeSpan(start: time("08:00"), end: time("09:30")),
            TimeSpan(start: time("09:00"), end: time("10:00")),
            TimeSpan(start: time("14:00"), end: time("15:00")),
        ]
        let merged = spans.merged()
        #expect(merged.count == 2)
        #expect(merged[0].text == "08:00–11:00")
        #expect(merged[1].text == "14:00–15:00")
    }

    @Test func durationIsCountedInMinutes() {
        #expect(TimeSpan(start: time("08:15"), end: time("09:45")).minutes == 90)
        #expect(TimeSpan(start: time("08:00"), minutes: 45).end.text == "08:45")
    }
}

/// Freie Luecken des laufenden Tages.
@Suite("Was heute noch frei ist")
struct RemainingSlotsTests {

    private func span(_ from: String, _ to: String) -> TimeSpan {
        TimeSpan(start: ClockTime(from)!, end: ClockTime(to)!)
    }

    private let slots = [
        TimeSpan(start: ClockTime("08:00")!, end: ClockTime("10:00")!),
        TimeSpan(start: ClockTime("11:30")!, end: ClockTime("13:30")!),
        TimeSpan(start: ClockTime("15:00")!, end: ClockTime("18:30")!),
    ]

    @Test func pastSlotsDisappear() {
        let remaining = slots.remaining(after: ClockTime("16:05")!)
        // Die laufende Luecke beginnt an der naechsten Viertelstunde.
        #expect(remaining.map(\.text) == ["16:15–18:30"])
    }

    @Test func earlyInTheDayEverythingIsStillThere() {
        #expect(slots.remaining(after: ClockTime("06:00")!) == slots)
    }

    @Test func aSlotAboutToEndIsNotWorthMentioning() {
        // Um 13:10 bleiben von 11:30–13:30 nur noch 15 Minuten ab 13:15.
        let remaining = slots.remaining(after: ClockTime("13:10")!)
        #expect(remaining.map(\.text) == ["15:00–18:30"])
    }

    @Test func lateAtNightNothingIsLeft() {
        #expect(slots.remaining(after: ClockTime("22:00")!).isEmpty)
    }

    @Test func quarterRounding() {
        #expect(ClockTime("16:05")!.ceiledToQuarter.text == "16:15")
        #expect(ClockTime("16:15")!.ceiledToQuarter.text == "16:15")
        #expect(ClockTime("16:46")!.ceiledToQuarter.text == "17:00")
    }
}
