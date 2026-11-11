import Foundation

/// Der Kalender der App: gregorianisch, lokale Zeitzone, **Woche beginnt montags**.
///
/// Alle Datumsrechnungen laufen ueber diese eine Instanz. Wuerde jede Stelle sich
/// ihren eigenen Kalender bauen, haette man frueher oder spaeter eine Ansicht, die
/// sonntags beginnt, und eine, die montags beginnt.
public let ldCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "de_DE")
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}()

/// Ein Kalendertag ohne Uhrzeit, serialisiert als `"YYYY-MM-DD"`.
///
/// Bewusst kein `Date`: Der Erledigt-Status haengt am *Tag*, nicht an einem
/// Zeitpunkt. Mit `Date` als Schluessel wuerde eine Umstellung der Zeitzone oder
/// eine Sommerzeitgrenze Eintraege auf den Nachbartag rutschen lassen.
public struct DateKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date) {
        let parts = ldCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(_ raw: String) {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static var today: DateKey { DateKey(Date()) }

    // MARK: - Umrechnung

    /// Mittag statt Mitternacht: An Tagen mit Zeitumstellung existiert 00:00 in
    /// manchen Zeitzonen nicht, 12:00 immer.
    public var date: Date {
        ldCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    public var rawValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { rawValue }

    // MARK: - Rechnen

    public func adding(days: Int) -> DateKey {
        DateKey(ldCalendar.date(byAdding: .day, value: days, to: date) ?? date)
    }

    public func adding(months: Int) -> DateKey {
        DateKey(ldCalendar.date(byAdding: .month, value: months, to: date) ?? date)
    }

    /// Abstand in ganzen Tagen: positiv, wenn `other` spaeter liegt.
    public func days(until other: DateKey) -> Int {
        ldCalendar.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    /// Wochentag in der Zaehlung der Spezifikation: 0 = Sonntag ... 6 = Samstag.
    public var weekdayIndex: Int {
        (ldCalendar.component(.weekday, from: date) - 1) % 7
    }

    public var isWeekend: Bool {
        weekdayIndex == 0 || weekdayIndex == 6
    }

    /// Kalenderwoche nach ISO 8601 - die Zahl, die auch im
    /// Vorlesungsverzeichnis steht.
    ///
    /// `ldCalendar` ist dafuer eingerichtet: Woche ab Montag, und eine Woche
    /// gehoert zu dem Jahr, in dem mindestens vier ihrer Tage liegen.
    public var weekOfYear: Int {
        ldCalendar.component(.weekOfYear, from: date)
    }

    /// Montag der Woche, in der dieser Tag liegt.
    public var startOfWeek: DateKey {
        adding(days: -((weekdayIndex + 6) % 7))
    }

    public var startOfMonth: DateKey {
        DateKey(year: year, month: month, day: 1)
    }

    public var daysInMonth: Int {
        ldCalendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DateKey(raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Ungueltiges Datum: \(raw)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: DateKey, rhs: DateKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Ohne diese Konformitaet kodiert `JSONEncoder` ein `[DateKey: X]` als flache
/// Liste abwechselnder Schluessel und Werte statt als JSON-Objekt.
extension DateKey: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringKey(rawValue)
    }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }

    private struct StringKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
