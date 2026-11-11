import Foundation

/// Eine Uhrzeit ohne Datum, z. B. `08:15`.
///
/// Intern Minuten seit Mitternacht, in der Datei `"HH:MM"`. Das Rechnen will
/// Zahlen, der Mensch, der die Datei aufmacht, will eine Uhrzeit lesen - beides
/// geht, wenn die Umrechnung an genau einer Stelle steckt.
///
/// Bewusst kein `Date`: Eine Vorlesung beginnt um Viertel nach acht, nicht an
/// einem Zeitpunkt. Mit `Date` haengte an jeder Uhrzeit ein Datum, das niemand
/// gemeint hat - und das bei Zeitumstellungen verrutscht.
public struct ClockTime: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {

    /// Minuten seit Mitternacht, 0 bis 1439.
    public let minutes: Int

    public init(minutes: Int) {
        self.minutes = Swift.min(Swift.max(minutes, 0), 24 * 60 - 1)
    }

    public init(hour: Int, minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    /// Aus `"HH:MM"`. Alles andere ergibt `nil`.
    public init?(_ raw: String) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// `"08:15"` - die Form, die auch in der Datei steht.
    public var text: String { String(format: "%02d:%02d", hour, minute) }

    public var description: String { text }

    /// Kurzform fuer enge Stellen: `"8"` statt `"08:00"`, aber `"8:15"`, wenn
    /// Minuten dranhaengen.
    public var shortText: String {
        minute == 0 ? "\(hour)" : "\(hour):\(String(format: "%02d", minute))"
    }

    public func adding(minutes delta: Int) -> ClockTime {
        ClockTime(minutes: minutes + delta)
    }

    /// Volle Stunde davor - fuer den Anfang einer Zeitachse.
    public var flooredToHour: ClockTime { ClockTime(hour: hour) }

    /// Volle Stunde danach, falls die Uhrzeit nicht schon darauf liegt.
    public var ceiledToHour: ClockTime {
        minute == 0 ? self : ClockTime(minutes: Swift.min((hour + 1) * 60, 24 * 60 - 1))
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutes < rhs.minutes
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ClockTime(raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Ungueltige Uhrzeit: \(raw)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// Eine Zeitspanne innerhalb eines Tages, z. B. `08:15–09:45`.
///
/// Das Ende ist ausschliesslich: Ein Kurs bis 10:00 und einer ab 10:00 stossen
/// aneinander, ueberschneiden sich aber nicht. Ohne diese Festlegung meldete die
/// App bei jedem Doppelblock einen Konflikt.
public struct TimeSpan: Hashable, Sendable, Comparable {
    public let start: ClockTime
    public let end: ClockTime

    /// Ein Ende vor dem Anfang gibt es nicht - es wird auf den Anfang gezogen.
    public init(start: ClockTime, end: ClockTime) {
        self.start = start
        self.end = Swift.max(start, end)
    }

    public init(start: ClockTime, minutes: Int) {
        self.init(start: start, end: start.adding(minutes: Swift.max(minutes, 0)))
    }

    public var minutes: Int { end.minutes - start.minutes }

    public func overlaps(_ other: TimeSpan) -> Bool {
        start < other.end && other.start < end
    }

    public func contains(_ time: ClockTime) -> Bool {
        time >= start && time < end
    }

    /// `"08:15–09:45"`, mit Halbgeviertstrich wie im Stundenplan ueblich.
    public var text: String { "\(start.text)–\(end.text)" }

    public static func < (lhs: TimeSpan, rhs: TimeSpan) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}

public extension Array where Element == TimeSpan {

    /// Legt Ueberschneidungen und direkt Anschliessendes zusammen.
    ///
    /// Grundlage der Luecken-Suche: Erst wenn aus drei sich ueberlappenden
    /// Bloecken einer geworden ist, ist das, was dazwischen bleibt, wirklich frei.
    func merged() -> [TimeSpan] {
        let sorted = self.sorted()
        var result: [TimeSpan] = []

        for span in sorted {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1] = TimeSpan(
                    start: last.start,
                    end: Swift.max(last.end, span.end)
                )
            } else {
                result.append(span)
            }
        }
        return result
    }
}

public extension ClockTime {
    /// Die naechste volle Viertelstunde - auf ihr liegend bleibt sie stehen.
    var ceiledToQuarter: ClockTime {
        let rest = minutes % 15
        return rest == 0 ? self : adding(minutes: 15 - rest)
    }
}

public extension Array where Element == TimeSpan {

    /// Was von diesen Luecken ab einer Uhrzeit noch uebrig ist.
    ///
    /// Fuer den laufenden Tag: Um vier Uhr nachmittags ist „frei 08:00–09:45"
    /// keine Auskunft mehr, sondern Rauschen. Vergangene Luecken fallen weg,
    /// eine laufende beginnt bei der naechsten Viertelstunde - und zaehlt nur,
    /// wenn dann noch genug von ihr bleibt.
    func remaining(after now: ClockTime, minimumMinutes: Int = 30) -> [TimeSpan] {
        let from = now.ceiledToQuarter
        return compactMap { slot in
            guard slot.end > from else { return nil }
            let trimmed = TimeSpan(start: Swift.max(slot.start, from), end: slot.end)
            return trimmed.minutes >= minimumMinutes ? trimmed : nil
        }
    }
}
