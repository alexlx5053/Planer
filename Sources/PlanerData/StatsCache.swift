import Foundation
import PlanerCore

/// Zwischenspeicher fuer alles, was aus dem Bestand errechnet wird.
///
/// Der Anlass ist die Bauweise von SwiftUI: Eine Ansicht liest ihre Werte
/// waehrend des Aufbaus mehrfach - die Tagesansicht greift ein Dutzend Mal auf
/// den Tagesinhalt zu, fuer Zaehler, Listen und Animationen. Ohne
/// Zwischenspeicher wuerde jeder dieser Zugriffe erneut filtern und sortieren.
///
/// Wichtig ist, wie fein verworfen wird: Beim Abhaken aendert sich genau ein Tag
/// (dessen Reihenfolge sich allerdings mitverschiebt, weil Erledigtes nach unten
/// rutscht), bei einer Aenderung am Eintrag dagegen jeder Tag, an dem er
/// vorkommt - dann wird alles verworfen.
final class StatsCache {
    private var stats: [DateKey: DayStats] = [:]
    private var agendas: [DateKey: DayAgenda] = [:]
    private var streak: Int?
    /// Je Anfrage (Anzahl, Vorschau in Tagen) getrennt gemerkt.
    ///
    /// Frueher gab es hier nur einen Platz. Die Seitenspalte fragt nach fuenf,
    /// die Menueleiste nach acht - wer zuerst fragte, bestimmte, wie viele der
    /// andere bekam.
    private var upcoming: [UpcomingKey: [UpcomingEvent]] = [:]

    private struct UpcomingKey: Hashable {
        let limit: Int
        let horizon: Int
    }

    // MARK: - Lesen

    func agenda(for day: DateKey, state: DashboardState, today: DateKey) -> DayAgenda {
        if let cached = agendas[day] { return cached }
        let computed = state.agenda(for: day, today: today)
        agendas[day] = computed
        return computed
    }

    func stats(for day: DateKey, state: DashboardState, today: DateKey) -> DayStats {
        if let cached = stats[day] { return cached }
        let computed = state.stats(for: day, today: today)
        stats[day] = computed
        return computed
    }

    func currentStreak(state: DashboardState, today: DateKey) -> Int {
        if let streak { return streak }
        let computed = state.currentStreak(today: today)
        streak = computed
        return computed
    }

    func upcomingEvents(state: DashboardState, today: DateKey, limit: Int,
                        horizon: Int = 90) -> [UpcomingEvent] {
        let key = UpcomingKey(limit: limit, horizon: horizon)
        if let cached = upcoming[key] { return cached }
        let computed = state.upcomingEvents(from: today, limit: limit, within: horizon)
        upcoming[key] = computed
        return computed
    }

    // MARK: - Verwerfen

    /// Nach dem Abhaken. Betroffen sind der Tag selbst - auch seine Reihenfolge,
    /// weil Erledigtes nach unten rutscht -, die Serie, weil sie ueber Tage
    /// hinweg zaehlt, und die Terminvorschau, aus der Abgehaktes verschwindet.
    func invalidate(_ day: DateKey) {
        stats.removeValue(forKey: day)
        agendas.removeValue(forKey: day)
        streak = nil
        upcoming.removeAll()
    }

    func invalidateAll() {
        stats.removeAll(keepingCapacity: true)
        agendas.removeAll(keepingCapacity: true)
        streak = nil
        upcoming.removeAll()
    }
}
