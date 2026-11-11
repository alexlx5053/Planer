import Foundation

/// Ein gesetzlicher Feiertag.
public struct Holiday: Hashable, Sendable {
    public let name: String
    public let day: DateKey

    public init(name: String, day: DateKey) {
        self.name = name
        self.day = day
    }
}

/// Gesetzliche Feiertage in Bayern. (Spezifikation 4.18)
///
/// Neun feste Termine, vier bewegliche - alle vier haengen am Ostersonntag, der
/// sich nach dem ersten Vollmond im Fruehling richtet und deshalb gerechnet
/// werden muss.
public enum Holidays {

    /// Ostersonntag nach dem anonymen gregorianischen Verfahren (Gauss/Meeus).
    ///
    /// Die Zwischenwerte tragen die Buchstaben des Originals; sie einzeln zu
    /// benennen wuerde das Verfahren nicht verstaendlicher machen, weil sie
    /// keine eigene Bedeutung haben.
    public static func easterSunday(year: Int) -> DateKey {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return DateKey(year: year, month: month, day: day)
    }

    /// Alle bayerischen Feiertage eines Jahres, nach Datum sortiert.
    public static func inBavaria(year: Int) -> [Holiday] {
        let easter = easterSunday(year: year)

        let holidays = [
            Holiday(name: "Neujahr", day: DateKey(year: year, month: 1, day: 1)),
            Holiday(name: "Heilige Drei Könige", day: DateKey(year: year, month: 1, day: 6)),
            Holiday(name: "Karfreitag", day: easter.adding(days: -2)),
            Holiday(name: "Ostermontag", day: easter.adding(days: 1)),
            Holiday(name: "Tag der Arbeit", day: DateKey(year: year, month: 5, day: 1)),
            Holiday(name: "Christi Himmelfahrt", day: easter.adding(days: 39)),
            Holiday(name: "Pfingstmontag", day: easter.adding(days: 50)),
            Holiday(name: "Fronleichnam", day: easter.adding(days: 60)),
            Holiday(name: "Mariä Himmelfahrt", day: DateKey(year: year, month: 8, day: 15)),
            Holiday(name: "Tag der Deutschen Einheit", day: DateKey(year: year, month: 10, day: 3)),
            Holiday(name: "Allerheiligen", day: DateKey(year: year, month: 11, day: 1)),
            Holiday(name: "1. Weihnachtstag", day: DateKey(year: year, month: 12, day: 25)),
            Holiday(name: "2. Weihnachtstag", day: DateKey(year: year, month: 12, day: 26)),
        ]
        return holidays.sorted { $0.day < $1.day }
    }

    /// Name des Feiertags an diesem Tag, sonst `nil`.
    ///
    /// Die Jahresliste wird zwischengespeichert: Das Monatsraster fragt 42-mal
    /// nacheinander, und dreizehn Feiertage jedes Mal neu zu rechnen waere
    /// Verschwendung.
    public static func name(on day: DateKey) -> String? {
        cache.name(on: day)
    }

    public static func isHoliday(_ day: DateKey) -> Bool {
        name(on: day) != nil
    }

    private static let cache = HolidayCache()
}

/// Jahresweiser Zwischenspeicher, abgesichert fuer den Zugriff aus mehreren
/// Aufgaben heraus.
private final class HolidayCache: @unchecked Sendable {
    private var byYear: [Int: [DateKey: String]] = [:]
    private let lock = NSLock()

    func name(on day: DateKey) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let year = byYear[day.year] { return year[day] }

        // Zwei Feiertage koennen auf denselben Tag fallen (2008: Tag der
        // Arbeit und Christi Himmelfahrt) - dann werden die Namen verbunden.
        let table = Dictionary(
            Holidays.inBavaria(year: day.year).map { ($0.day, $0.name) },
            uniquingKeysWith: { first, second in "\(first) · \(second)" }
        )
        byYear[day.year] = table
        return table[day]
    }
}
