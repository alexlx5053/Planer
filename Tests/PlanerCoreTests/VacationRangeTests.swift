import Testing
@testable import PlanerCore

/// Urlaubszeitraeume zusammenfassen und einzelne Tage herausnehmen.
@Suite("Urlaubszeiträume")
struct VacationRangeTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private func range(_ from: String, _ to: String) -> VacationRange {
        VacationRange(start: day(from), end: day(to))
    }

    // MARK: - Zusammenfassen

    @Test func mergesDuplicates() {
        let ranges = [range("2026-09-04", "2026-09-04"), range("2026-09-04", "2026-09-04")]
        #expect(ranges.normalized().count == 1)
    }

    @Test func mergesOverlapping() {
        let ranges = [range("2026-09-01", "2026-09-05"), range("2026-09-03", "2026-09-08")]
        let merged = ranges.normalized()

        #expect(merged.count == 1)
        #expect(merged[0].start == day("2026-09-01"))
        #expect(merged[0].end == day("2026-09-08"))
    }

    /// Zwei Zeitraeume, die direkt aneinander anschliessen, sind einer.
    @Test func mergesAdjacent() {
        let ranges = [range("2026-09-01", "2026-09-03"), range("2026-09-04", "2026-09-06")]
        let merged = ranges.normalized()

        #expect(merged.count == 1)
        #expect(merged[0].end == day("2026-09-06"))
    }

    @Test func keepsSeparateRangesApart() {
        let ranges = [range("2026-09-01", "2026-09-03"), range("2026-09-20", "2026-09-25")]
        #expect(ranges.normalized().count == 2)
    }

    // MARK: - Tag herausnehmen

    @Test func removesASingleDayRange() {
        let ranges = [range("2026-09-15", "2026-09-15")]
        #expect(ranges.removing(day("2026-09-15")).isEmpty)
    }

    /// Ein Tag mitten im Zeitraum teilt ihn in zwei Stuecke.
    @Test func splitsARangeAroundTheRemovedDay() {
        let ranges = [range("2026-09-10", "2026-09-20")]
        let result = ranges.removing(day("2026-09-15"))

        #expect(result.count == 2)
        #expect(result[0].start == day("2026-09-10"))
        #expect(result[0].end == day("2026-09-14"))
        #expect(result[1].start == day("2026-09-16"))
        #expect(result[1].end == day("2026-09-20"))
    }

    @Test func trimsTheEdgeOfARange() {
        let result = [range("2026-09-10", "2026-09-20")].removing(day("2026-09-10"))

        #expect(result.count == 1)
        #expect(result[0].start == day("2026-09-11"))
    }

    @Test func leavesOtherRangesAlone() {
        let ranges = [range("2026-09-01", "2026-09-02"), range("2026-09-15", "2026-09-15")]
        let result = ranges.removing(day("2026-09-15"))

        #expect(result.count == 1)
        #expect(result[0].start == day("2026-09-01"))
    }

    /// Der eigentliche Fall: Nach dem Aufheben stehen die Gewohnheiten wieder da.
    @Test func habitsReturnAfterClearingTheDay() {
        let today = day("2026-09-15")
        var state = DashboardState(habits: [HabitItem(title: "Duolingo", startDate: today)])
        state.vacationRanges = [range("2026-09-15", "2026-09-15")]

        #expect(state.habits(on: today, today: today).isEmpty, "Am Urlaubstag pausieren sie")

        state.vacationRanges = state.vacationRanges.removing(today)
        #expect(state.habits(on: today, today: today).count == 1)
    }
}
