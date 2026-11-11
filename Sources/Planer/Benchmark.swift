import Foundation
import PlanerCore
import PlanerData

/// Laufzeitmessung mit einem realistisch grossen Bestand.
///
/// Die Zusage lautet: Abhaken bleibt auch bei jahrelanger Historie ohne
/// spuerbare Verzoegerung. „Spuerbar" beginnt bei etwa 16 ms - eine Bildfolge
/// bei 60 Hz. Auf einem 120-Hz-Bildschirm bleiben 8 ms.
@MainActor
enum Benchmark {

    static func run() {
        let store = SampleData.largeStore()
        let today = store.today

        print("Bestand: \(store.state.tasks.count) Aufgaben, \(store.state.habits.count) Gewohnheiten, "
              + "\(store.state.completions.totalCount) Markierungen")

        measure("Tageswerte erstmalig (42 Tage im Kalender)") {
            for offset in 0..<42 { _ = store.stats(for: today.adding(days: -offset)) }
        }
        measure("Tageswerte erneut (aus dem Zwischenspeicher)") {
            for offset in 0..<42 { _ = store.stats(for: today.adding(days: -offset)) }
        }
        measure("Streak erstmalig") { _ = store.streak }
        measure("Streak erneut") { _ = store.streak }

        let habit = store.state.habits[0]
        measure("Abhaken samt Neuberechnung von Ring, Streak und Kalender") {
            store.toggleCompletion(habit.id, on: today)
            _ = store.stats(for: today)
            _ = store.streak
            for offset in 0..<42 { _ = store.stats(for: today.adding(days: -offset)) }
        }

        exit(0)
    }

    private static func measure(_ label: String, _ work: () -> Void) {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let verdict = milliseconds < 8 ? "gut" : (milliseconds < 16 ? "grenzwertig" : "ZU LANGSAM")
        print(String(format: "%-52s %7.2f ms  %@", (label as NSString).utf8String!, milliseconds, verdict))
    }
}
