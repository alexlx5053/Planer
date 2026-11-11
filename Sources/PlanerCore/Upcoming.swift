import Foundation

/// Das naechste offene Vorkommen eines Termins.
public struct UpcomingEvent: Identifiable, Hashable, Sendable {
    public let event: EventItem
    public let day: DateKey
    /// Tage bis dahin: 0 = heute, 1 = morgen.
    public let daysAway: Int

    public var id: UUID { event.id }

    public init(event: EventItem, day: DateKey, daysAway: Int) {
        self.event = event
        self.day = day
        self.daysAway = daysAway
    }

    /// Kurzform fuer die Seitenspalte.
    public var shortLabel: String {
        switch daysAway {
        case 0: "heute"
        case 1: "morgen"
        default: "in \(daysAway) T"
        }
    }

    /// Ausgeschriebene Form fuer Sprachausgabe und Kurzhinweise.
    public var longLabel: String {
        switch daysAway {
        case 0: "heute"
        case 1: "morgen"
        case 2: "übermorgen"
        default: "in \(daysAway) Tagen"
        }
    }
}

public extension DashboardState {

    /// Die naechsten offenen Termine, der naechstliegende zuerst.
    /// (Spezifikation 4.12)
    ///
    /// Je Termin zaehlt nur sein *naechstes* offenes Vorkommen. Ein woechentliches
    /// Training soll einmal in der Liste stehen und nicht dreizehnmal.
    ///
    /// Abgehakte Vorkommen werden uebersprungen: Wer heute schon beim Zahnarzt
    /// war, will nicht bis Mitternacht lesen, dass er „heute" hin muss.
    func upcomingEvents(
        from today: DateKey = .today,
        limit: Int = 5,
        within horizon: Int = 90
    ) -> [UpcomingEvent] {
        var found: [UpcomingEvent] = []
        var seen: Set<UUID> = []

        for offset in 0...horizon {
            let day = today.adding(days: offset)

            for event in events(on: day, today: today) where !seen.contains(event.id) {
                guard !completions.isDone(event.id, on: day) else { continue }
                seen.insert(event.id)
                found.append(UpcomingEvent(event: event, day: day, daysAway: offset))
            }

            // Die Tage werden aufsteigend abgelaufen: Was hier schon gefunden
            // ist, liegt naeher als alles Weitere.
            if found.count >= limit || seen.count == events.count { break }
        }

        return Array(found.prefix(limit))
    }
}

// MARK: - Gliederung der Gesamtliste

/// Ein Abschnitt der Terminliste: „Heute", „Diese Woche", „November 2026".
public struct UpcomingSection: Sendable {
    public let title: String
    public var items: [UpcomingEvent]
}

public enum UpcomingGrouping {

    /// Ordnet Termine ihren Abschnitten zu, in zeitlicher Reihenfolge.
    ///
    /// Je weiter weg, desto groeber: heute, morgen, diese Woche, naechste
    /// Woche, danach monatsweise. Niemand plant den Maerz tageweise.
    public static func sections(for items: [UpcomingEvent], today: DateKey) -> [UpcomingSection] {
        var result: [UpcomingSection] = []
        for item in items {
            let title = title(for: item, today: today)
            if result.last?.title == title {
                result[result.count - 1].items.append(item)
            } else {
                result.append(UpcomingSection(title: title, items: [item]))
            }
        }
        return result
    }

    public static func title(for item: UpcomingEvent, today: DateKey) -> String {
        if item.daysAway == 0 { return "Heute" }
        if item.daysAway == 1 { return "Morgen" }
        let thisWeek = today.startOfWeek
        if item.day.startOfWeek == thisWeek { return "Diese Woche" }
        if item.day.startOfWeek == thisWeek.adding(days: 7) { return "Nächste Woche" }
        return monthTitle(item.day)
    }

    static func monthTitle(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: day.date)
    }
}
