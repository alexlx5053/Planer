import Foundation

// MARK: - Entwurf

/// Ein aus Text gelesener Eintrag, bevor er angelegt wird.
///
/// Ein Entwurf, kein Eintrag: Er steht erst zur Ansicht da, und nichts landet im
/// Bestand, bevor man es bestaetigt hat. Ein Leser, der sich irrt, darf nichts
/// kaputt machen.
public struct EntryDraft: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case event, task

        public var label: String {
            switch self {
            case .event: "Termin"
            case .task: "Aufgabe"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var title: String
    public var date: DateKey
    /// Nur bei Terminen von Belang - Aufgaben haben keine Uhrzeit.
    public var time: ClockTime?
    public var durationMinutes: Int?
    public var notes: String
    /// Soll der Entwurf angelegt werden?
    public var isIncluded: Bool
    /// Stand das Datum im Text, oder ist „heute" nur die Annahme?
    public var hasExplicitDate: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        date: DateKey,
        time: ClockTime? = nil,
        durationMinutes: Int? = nil,
        notes: String = "",
        isIncluded: Bool = true,
        hasExplicitDate: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.time = time
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.isIncluded = isIncluded
        self.hasExplicitDate = hasExplicitDate
    }

    /// Die Zeitspanne, falls es ein Termin mit Uhrzeit ist.
    public var span: TimeSpan? {
        guard kind == .event, let time else { return nil }
        return TimeSpan(start: time, minutes: durationMinutes ?? EventItem.assumedDuration)
    }

    /// Der Entwurf als Termin.
    public func makeEvent() -> EventItem {
        EventItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: date,
            time: time?.text,
            durationMinutes: time == nil ? nil : durationMinutes,
            notes: notes
        )
    }

    /// Der Entwurf als Aufgabe.
    public func makeTask() -> TaskItem {
        TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startDate: date)
    }
}

// MARK: - Leser

/// Liest Datum, Uhrzeit und Dauer aus frei geschriebenem Text.
///
/// **Rechnen, nicht raten.** Ein Sprachmodell versteht, dass „die Klausur findet
/// am 12.2. statt" ein Termin ist - aber es verrechnet sich beim Jahr, bei der
/// Dauer und beim Wochentag. Deshalb ist die Arbeit geteilt: Das Modell (wenn es
/// eines gibt) sagt, *was* etwas ist und wie es heisst. *Wann* es ist, bestimmt
/// immer dieser Leser, mit festen Regeln, die sich pruefen lassen.
///
/// Ohne Modell arbeitet er allein: Er zerlegt den Text in Zeilen und Saetze und
/// macht aus jedem, in dem ein Datum oder eine Uhrzeit steht, einen Entwurf.
public enum QuickParser {

    // MARK: Zeitpunkt

    /// Was sich in einem Textstueck an Zeitangaben fand.
    public struct Moment: Sendable {
        public var date: DateKey?
        /// Zweites Datum eines Zeitraums: „7.12. – 18.12.".
        public var endDate: DateKey?
        public var time: ClockTime?
        public var durationMinutes: Int?
        /// Stand ein „bis", „spaetestens" oder „Frist" vor dem Datum?
        public var isDeadline = false
        /// Der Text ohne die Zeitangaben - Grundlage fuer den Titel.
        public var remainder = ""

        public var hasWhen: Bool { date != nil || time != nil }
    }

    /// Sucht in einem Textstueck nach dem ersten Datum und der ersten Uhrzeit.
    public static func moment(in text: String, today: DateKey) -> Moment {
        var scan = Scan(text)
        var result = Moment()
        let source = text as NSString
        func deadline(before range: NSRange) -> Bool { Scan.isDeadline(before: range, in: source) }

        // 0. „Fr 14h", „Do 18 Uhr": ein abgekuerzter Wochentag direkt vor einer
        //    Uhrzeit. Vorab, solange die Uhrzeit noch dasteht - nur an ihr ist
        //    zu erkennen, dass „Do" hier ein Tag ist und kein Wort.
        var abbreviatedWeekday: Int?
        scan.each(Patterns.weekdayBeforeTime) { match, text in
            guard let weekday = weekdayIndex(abbreviation: match.string(1, in: text)) else {
                return false
            }
            if abbreviatedWeekday == nil { abbreviatedWeekday = weekday }
            return true
        }

        // 1. Uhrzeiten zuerst. „13.15 Uhr" saehe sonst aus wie der Anfang
        //    eines Datums.
        for pattern in [Patterns.rangeColon, Patterns.rangeDotted, Patterns.rangeHours] {
            scan.each(pattern) { match, text in
                let startHour = match.int(1, in: text), startMinute = match.int(2, in: text) ?? 0
                let endHour = match.int(3, in: text), endMinute = match.int(4, in: text) ?? 0
                guard let startHour, let endHour,
                      let start = clock(startHour, startMinute), let end = clock(endHour, endMinute),
                      end > start
                else { return false }
                if result.time == nil {
                    result.time = start
                    result.durationMinutes = end.minutes - start.minutes
                }
                return true
            }
        }

        for pattern in [Patterns.timeColon, Patterns.timeDotted, Patterns.timeHour, Patterns.timePM,
                        Patterns.timeH] {
            scan.each(pattern) { match, text in
                guard var hour = match.int(1, in: text) else { return false }
                let minute = match.int(2, in: text) ?? 0
                if pattern === Patterns.timePM, hour < 12 { hour += 12 }
                // „14h" ist eine Uhrzeit, „2h" eine Dauer - vor sechs Uhr
                // morgens verabredet sich niemand mit einem „h".
                if pattern === Patterns.timeH, hour < 6 { return false }
                guard let time = clock(hour, minute) else { return false }
                if result.time == nil { result.time = time }
                return true
            }
        }

        // 2. Ausgeschriebene Daten.
        scan.each(Patterns.dateISO) { match, text in
            guard let year = match.int(1, in: text), let month = match.int(2, in: text),
                  let day = match.int(3, in: text),
                  let date = validDate(year: year, month: month, day: day)
            else { return false }
            if result.date == nil {
                result.date = date
                result.isDeadline = deadline(before: match.range)
            }
            return true
        }

        for pattern in [Patterns.dateNumeric, Patterns.dateNumericShort, Patterns.dateSlash] {
            scan.each(pattern) { match, text in
                guard let day = match.int(1, in: text), let month = match.int(2, in: text) else {
                    return false
                }
                let year = match.int(3, in: text) ?? match.int(4, in: text)
                guard let date = resolve(day: day, month: month, year: year, today: today) else {
                    return false
                }
                if result.date == nil {
                    result.date = date
                    result.isDeadline = deadline(before: match.range)
                } else if result.endDate == nil {
                    result.endDate = date
                }
                return true
            }
        }

        scan.each(Patterns.dateDayMonth) { match, text in
            guard let day = match.int(1, in: text),
                  let month = monthNumber(match.string(2, in: text)),
                  let date = resolve(day: day, month: month, year: match.int(3, in: text), today: today)
            else { return false }
            if result.date == nil {
                result.date = date
                result.isDeadline = deadline(before: match.range)
            } else if result.endDate == nil {
                result.endDate = date
            }
            return true
        }

        scan.each(Patterns.dateMonthDay) { match, text in
            guard let month = monthNumber(match.string(1, in: text)),
                  let day = match.int(2, in: text),
                  let date = resolve(day: day, month: month, year: match.int(3, in: text), today: today)
            else { return false }
            if result.date == nil {
                result.date = date
                result.isDeadline = deadline(before: match.range)
            } else if result.endDate == nil {
                result.endDate = date
            }
            return true
        }

        // 3. „um 14" - erst jetzt, damit „um 14.11." nicht als Uhrzeit endet.
        scan.each(Patterns.timeAtHour) { match, text in
            guard let hour = match.int(1, in: text), let time = clock(hour, 0) else { return false }
            if result.time == nil { result.time = time }
            return true
        }

        // 4. Bezogene Angaben: heute, morgen, naechsten Montag, in drei Tagen.
        //    Ein ausgeschriebenes Datum hat Vorrang - „Freitag, 12.2." meint den
        //    12.2., der Wochentag ist nur Beiwerk und verschwindet aus dem Titel.
        let nextWeek = scan.consumeFirst(Patterns.nextWeek) != nil

        scan.each(Patterns.weekday) { match, text in
            guard let weekday = weekdayIndex(match.string(2, in: text)) else { return false }
            if result.date == nil {
                let qualifier = match.string(1, in: text)?.lowercased() ?? ""
                var date = nextWeek
                    ? today.startOfWeek.adding(days: 7 + (weekday + 6) % 7)
                    : nextOccurrence(of: weekday, after: today)
                if qualifier.hasPrefix("übernächst") { date = date.adding(days: 7) }
                result.date = date
                result.isDeadline = deadline(before: match.range)
                    || qualifier == "bis"
            }
            return true
        }

        if result.date == nil, let abbreviatedWeekday {
            result.date = nextWeek
                ? today.startOfWeek.adding(days: 7 + (abbreviatedWeekday + 6) % 7)
                : nextOccurrence(of: abbreviatedWeekday, after: today)
        }

        if result.date == nil, nextWeek {
            result.date = today.startOfWeek.adding(days: 7)
        }

        scan.each(Patterns.relativeDay) { match, text in
            let word = match.string(1, in: text)?.lowercased() ?? ""
            let offset: Int
            switch word {
            case "heute", "today": offset = 0
            case "übermorgen": offset = 2
            default: offset = 1
            }
            if result.date == nil {
                result.date = today.adding(days: offset)
                result.isDeadline = deadline(before: match.range)
            }
            return true
        }

        scan.each(Patterns.relativeSpan) { match, text in
            guard let count = number(match.string(1, in: text)),
                  let unit = match.string(2, in: text)?.lowercased()
            else { return false }
            if result.date == nil {
                if unit.hasPrefix("tag") || unit.hasPrefix("day") {
                    result.date = today.adding(days: count)
                } else if unit.hasPrefix("woche") || unit.hasPrefix("week") {
                    result.date = today.adding(days: count * 7)
                } else {
                    result.date = today.adding(months: count)
                }
            }
            return true
        }

        // 5. Dauer - nur, wenn es eine Uhrzeit gibt und noch kein Ende. Sonst
        //    wuerde aus der Aufgabe „30 Minuten lesen" ein „lesen".
        if result.time != nil, result.durationMinutes == nil {
            scan.each(Patterns.duration) { match, text in
                guard let raw = match.string(1, in: text)?.replacingOccurrences(of: ",", with: "."),
                      let value = Double(raw),
                      let unit = match.string(2, in: text)?.lowercased()
                else { return false }
                let minutes = unit.hasPrefix("m") ? Int(value) : Int((value * 60).rounded())
                guard (5...12 * 60).contains(minutes) else { return false }
                if result.durationMinutes == nil { result.durationMinutes = minutes }
                return true
            }
        }

        if let date = result.date, let end = result.endDate, end <= date {
            result.endDate = nil
        }

        result.remainder = scan.remainder()
        return result
    }

    // MARK: Entwuerfe

    /// Laenger darf ein Text nicht sein, um gelesen zu werden.
    public static let characterLimit = 20_000

    /// Zerlegt einen Text in Entwuerfe - ohne Sprachmodell, nur mit Regeln.
    public static func drafts(from text: String, today: DateKey) -> [EntryDraft] {
        // Eingefuegter Text kommt von irgendwoher. Eine Obergrenze haelt den
        // Leser schnell, auch wenn jemand versehentlich ein ganzes Buch
        // einfuegt - mehr als das hier ist ohnehin keine Mail mehr.
        let text = String(text.prefix(characterLimit))
        var drafts: [EntryDraft] = []
        /// Ein Datum aus einer Zeile, die nur aus dem Datum bestand - es gilt
        /// fuer die Zeilen darunter, wie die Ueberschrift eines Tages.
        var contextDate: DateKey?
        var lastHeaderDate: DateKey?

        for line in text.components(separatedBy: .newlines) {
            var lineHadEntry = false
            var lastTitleInLine = ""

            for sentence in sentences(in: line).flatMap({ clauses(in: $0, today: today) }) {
                let found = moment(in: sentence, today: today)
                let title = cleanTitle(found.remainder)

                guard found.hasWhen else {
                    // Unter einer Datumsueberschrift ist jede Zeile ein eigener
                    // Eintrag an diesem Tag - auch ohne Uhrzeit.
                    if let contextDate, !title.isEmpty, !isGreeting(sentence) {
                        var draft = makeDraft(
                            title: title, kindHint: kindHint(in: sentence) ?? .task,
                            found: found, fallbackDate: contextDate, snippet: sentence
                        )
                        draft.hasExplicitDate = true
                        drafts.append(draft)
                        lineHadEntry = true
                        continue
                    }

                    // Ein Nachsatz zum Termin davor: „Raum 12", „Bitte
                    // puenktlich". Er wandert in dessen Notiz.
                    if lineHadEntry || !drafts.isEmpty, isNote(sentence),
                       let last = drafts.indices.last, drafts[last].kind == .event {
                        drafts[last].notes = [drafts[last].notes, sentence]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    }
                    continue
                }

                if title.isEmpty, found.time == nil, let date = found.date {
                    contextDate = date
                    lastHeaderDate = date
                    continue
                }

                // „Wir sehen uns am 20.11. und am 27.11.": Der zweite Termin hat
                // keinen eigenen Namen - er traegt den des ersten.
                let inherited = title.isEmpty && lineHadEntry ? lastTitleInLine : title
                var draft = makeDraft(
                    title: inherited,
                    kindHint: kindHint(in: sentence),
                    found: found,
                    fallbackDate: contextDate ?? today,
                    snippet: sentence
                )
                if contextDate != nil { draft.hasExplicitDate = true }
                drafts.append(draft)
                lineHadEntry = true
                if !title.isEmpty { lastTitleInLine = title }
            }
        }

        if !drafts.isEmpty { return drafts }

        // Nur ein Datum, sonst nichts: immerhin ein Termin an diesem Tag.
        if let lastHeaderDate {
            return [EntryDraft(kind: .event, title: "Termin", date: lastHeaderDate)]
        }

        // Kein einziges Datum im ganzen Text: Dann ist es eine Liste von Dingen,
        // die zu tun sind - jede Zeile eine Aufgabe fuer heute.
        return undatedTasks(from: text, today: today)
    }

    /// Baut einen Entwurf aus Angaben, die schon feststehen - Art und Titel vom
    /// Sprachmodell -, und rechnet das Wann aus dem zugehoerigen Textstueck.
    public static func draft(
        kind: EntryDraft.Kind?,
        title: String,
        snippet: String,
        today: DateKey
    ) -> EntryDraft? {
        let found = moment(in: snippet, today: today)
        let cleaned = cleanTitle(moment(in: title, today: today).remainder)
        let finalTitle = cleaned.isEmpty ? cleanTitle(found.remainder) : cleaned
        guard !finalTitle.isEmpty else { return nil }

        return makeDraft(
            title: finalTitle,
            kindHint: kind ?? kindHint(in: snippet),
            found: found,
            fallbackDate: today,
            snippet: snippet
        )
    }

    private static func makeDraft(
        title: String,
        kindHint: EntryDraft.Kind?,
        found: Moment,
        fallbackDate: DateKey,
        snippet: String
    ) -> EntryDraft {
        // Die Reihenfolge der Fragen:
        // 1. Eine Frist ist eine Aufgabe, auch mit Uhrzeit („bis Freitag 12 Uhr").
        // 2. Sonst macht eine Uhrzeit den Termin.
        // 3. Sonst entscheidet das Verb („abgeben", „kaufen") oder der Zusatz.
        // 4. Ein blosses Datum ist ein ganztaegiger Termin, nichts ist eine
        //    Aufgabe fuer heute.
        let kind: EntryDraft.Kind
        if found.isDeadline {
            kind = .task
        } else if let kindHint, found.time == nil || kindHint == .event {
            kind = kindHint
        } else if found.time != nil {
            kind = .event
        } else {
            kind = found.date != nil ? .event : .task
        }

        var finalTitle = title.isEmpty ? kind.label : title
        // Eine Aufgabe kennt keine Uhrzeit. Damit „bis 12 Uhr" nicht verloren
        // geht, wandert sie in den Titel.
        if kind == .task, let time = found.time {
            finalTitle += " (bis \(time.text))"
        }

        // Ein Zeitraum: Der Eintrag steht am ersten Tag, das Ende geht nicht
        // verloren, sondern steht im Titel - dort sieht man es auch in der
        // Liste.
        if let end = found.endDate {
            finalTitle += " (bis \(end.day).\(end.month).)"
        }

        return EntryDraft(
            kind: kind,
            title: finalTitle,
            date: found.date ?? fallbackDate,
            time: kind == .event ? found.time : nil,
            durationMinutes: kind == .event ? found.durationMinutes : nil,
            hasExplicitDate: found.date != nil
        )
    }

    private static func undatedTasks(from text: String, today: DateKey) -> [EntryDraft] {
        let lines = text.components(separatedBy: .newlines)
            .map { cleanTitle($0) }
            .filter { !$0.isEmpty && !isGreeting($0) }

        guard !lines.isEmpty else { return [] }

        // Ein langer Fliesstext ist keine Liste: Dann eine Aufgabe, der Rest
        // geht nicht verloren, sondern steht im Titel bis zur Grenze.
        if lines.count == 1 || lines.contains(where: { $0.count > 120 }) {
            return [EntryDraft(kind: .task, title: shortened(lines[0]), date: today,
                               hasExplicitDate: false)]
        }
        return lines.prefix(30).map {
            EntryDraft(kind: .task, title: shortened($0), date: today, hasExplicitDate: false)
        }
    }

    // MARK: Titel

    /// Macht aus dem, was nach dem Herausnehmen der Zeitangaben uebrig ist,
    /// einen Titel: ohne haengende Verhaeltniswoerter, ohne Aufzaehlungszeichen.
    public static func cleanTitle(_ raw: String) -> String {
        var text = raw

        // Verhaeltniswoerter, die vor einer herausgenommenen Zeitangabe standen:
        // „Zahnarzt am ▯ um ▯" -> „Zahnarzt". Mehrfach, weil sie sich reihen.
        for _ in 0..<4 {
            let before = text
            text = Patterns.danglingBefore.replace(in: text, with: "")
            text = Patterns.danglingAfter.replace(in: text, with: String(Scan.marker))
            if text == before { break }
        }

        text = text.replacingOccurrences(of: String(Scan.marker), with: " ")
        text = Patterns.leadIn.replace(in: text, with: "")
        text = Patterns.emptyBrackets.replace(in: text, with: " ")
        text = Patterns.repeatedPunctuation.replace(in: text, with: ",")
        text = Patterns.spaceBeforePunctuation.replace(in: text, with: "$1")
        text = Patterns.whitespace.replace(in: text, with: " ")
        text = text.trimmingCharacters(in: Self.edgeCharacters)
        text = Patterns.trailingFiller.replace(in: text, with: "")
        text = text.trimmingCharacters(in: Self.edgeCharacters)

        guard let first = text.first else { return "" }
        return shortened(first.uppercased() + text.dropFirst())
    }

    private static let edgeCharacters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",;:-–—|·•*>!?."))

    private static func shortened(_ title: String, limit: Int = 90) -> String {
        guard title.count > limit else { return title }
        let cut = title.prefix(limit)
        let lastSpace = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<lastSpace]).trimmingCharacters(in: edgeCharacters) + " …"
    }

    // MARK: Art

    /// Sagt der Text selbst, was er ist? „TODO:", „Termin:", ein Verb wie
    /// „abgeben".
    static func kindHint(in text: String) -> EntryDraft.Kind? {
        if Patterns.eventLabel.matches(text) { return .event }
        if Patterns.taskLabel.matches(text) || Patterns.taskVerb.matches(text) { return .task }
        return nil
    }

    private static func isGreeting(_ text: String) -> Bool {
        Patterns.greeting.matches(text)
    }

    /// Taugt ein Satz ohne Zeitangabe als Notiz zum Termin davor?
    private static func isNote(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return (3...160).contains(trimmed.count) && !isGreeting(trimmed)
    }

    // MARK: Saetze

    /// Trennt eine Zeile in Saetze, ohne an „12.2." oder „z.B." zu zerbrechen:
    /// Getrennt wird nur nach einem Punkt, vor dem mindestens zwei Buchstaben
    /// stehen und nach dem ein Grossbuchstabe folgt.
    static func sentences(in line: String) -> [String] {
        let marked = Patterns.sentenceBreak.replace(in: line, with: "$1\u{2}")
        return marked.components(separatedBy: "\u{2}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Trennt einen Satz an Kommas und „und", wenn darin mehrere Dinge mit
    /// je eigenem Datum stehen: „Hinflug 3. März 06:40, Rückflug 10. März
    /// 21:15" sind zwei Termine. Steht nur ein Datum im Satz, bleibt er ganz -
    /// sonst zerfiele „Gastvortrag, Mo 30.11., 17:00, Raum 12" in vier Teile.
    static func clauses(in sentence: String, today: DateKey) -> [String] {
        let marked = Patterns.clauseBreak.replace(in: sentence, with: "\u{2}")
        let parts = marked.components(separatedBy: "\u{2}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return [sentence] }

        let dated = parts.map { moment(in: $0, today: today).date != nil }
        guard dated.filter({ $0 }).count >= 2 else { return [sentence] }

        // Teile ohne eigenes Datum gehoeren zu dem davor.
        var result: [String] = []
        for (part, hasDate) in zip(parts, dated) {
            if hasDate || result.isEmpty {
                result.append(part)
            } else {
                result[result.count - 1] += ", " + part
            }
        }
        // Stand vor dem ersten datierten Teil noch etwas ohne Datum, gehoert es
        // zu diesem ersten.
        if result.count >= 2, moment(in: result[0], today: today).date == nil {
            result[1] = result[0] + ", " + result[1]
            result.removeFirst()
        }
        return result.count >= 2 ? result : [sentence]
    }

    // MARK: Rechnen

    private static func clock(_ hour: Int, _ minute: Int) -> ClockTime? {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            // „24 Uhr" meint Mitternacht - das Ende des Tages.
            return hour == 24 && minute == 0 ? ClockTime(hour: 23, minute: 59) : nil
        }
        return ClockTime(hour: hour, minute: minute)
    }

    /// Ein Datum gibt es nur, wenn der Kalender es kennt - kein 31.2.
    static func validDate(year: Int, month: Int, day: Int) -> DateKey? {
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else {
            return nil
        }
        let candidate = DateKey(year: year, month: month, day: day)
        // Der Kalender rollt ungueltige Tage weiter (31.2. -> 3.3.). Bleibt
        // das Datum nach Hin- und Rueckweg gleich, gab es den Tag wirklich.
        return DateKey(candidate.date) == candidate ? candidate : nil
    }

    /// Ergaenzt das Jahr, wenn keines dasteht: das naechste Mal, dass dieser
    /// Tag kommt. Am 10.11.2026 ist „12.2." der 12.2.2027 - niemand traegt
    /// einen Termin fuer den vergangenen Januar ein.
    static func resolve(day: Int, month: Int, year: Int?, today: DateKey) -> DateKey? {
        if let year {
            return validDate(year: year < 100 ? 2000 + year : year, month: month, day: day)
        }
        if let thisYear = validDate(year: today.year, month: month, day: day), thisYear >= today {
            return thisYear
        }
        return validDate(year: today.year + 1, month: month, day: day)
    }

    /// Der naechste Tag mit diesem Wochentag, heute ausgenommen: Wer am
    /// Dienstag „am Dienstag" schreibt, meint den naechsten - fuer heute sagt
    /// man „heute".
    static func nextOccurrence(of weekday: Int, after today: DateKey) -> DateKey {
        let distance = (weekday - today.weekdayIndex + 7) % 7
        return today.adding(days: distance == 0 ? 7 : distance)
    }

    private static func monthNumber(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let key = raw.lowercased().prefix(3)
        switch key {
        case "jan": return 1
        case "feb": return 2
        case "mär", "mar", "mrz", "mae": return 3
        case "apr": return 4
        case "mai", "may": return 5
        case "jun": return 6
        case "jul": return 7
        case "aug": return 8
        case "sep": return 9
        case "okt", "oct": return 10
        case "nov": return 11
        case "dez", "dec": return 12
        default: return nil
        }
    }

    /// 0 = Sonntag ... 6 = Samstag, wie ueberall in der App.
    private static func weekdayIndex(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        switch raw.lowercased().prefix(3) {
        case "son", "sun": return raw.lowercased().hasPrefix("sonna") ? 6 : 0
        case "mon": return 1
        case "die", "tue": return 2
        case "mit", "wed": return 3
        case "don", "thu": return 4
        case "fre", "fri": return 5
        case "sam", "sat": return 6
        default: return nil
        }
    }

    private static func weekdayIndex(abbreviation raw: String?) -> Int? {
        switch raw?.lowercased() {
        case "so": 0
        case "mo": 1
        case "di": 2
        case "mi": 3
        case "do": 4
        case "fr": 5
        case "sa": 6
        default: nil
        }
    }

    private static func number(_ raw: String?) -> Int? {
        guard let raw = raw?.lowercased() else { return nil }
        if let value = Int(raw) { return value }
        let words = ["ein": 1, "einem": 1, "einer": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4,
                     "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10]
        return words[raw]
    }
}

// MARK: - Abtasten

/// Der Text waehrend des Lesens.
///
/// Was als Zeitangabe erkannt ist, wird durch Leerraum ersetzt - gleich lang,
/// damit alle Fundstellen ihre Position behalten. So findet kein Muster eine
/// Stelle zweimal, und am Ende bleibt uebrig, was nicht Zeitangabe war.
private struct Scan {
    /// Platzhalter fuer eine herausgenommene Zeitangabe.
    static let marker: Character = "\u{1}"

    private let original: NSString
    private let masked: NSMutableString
    private var consumed: [NSRange] = []

    init(_ text: String) {
        original = text as NSString
        masked = NSMutableString(string: text)
    }

    /// Geht alle Fundstellen eines Musters durch. Gibt die Auswertung `true`
    /// zurueck, gilt die Stelle als Zeitangabe und wird herausgenommen.
    mutating func each(_ pattern: Pattern, _ body: (NSTextCheckingResult, NSString) -> Bool) {
        let snapshot = masked.copy() as! NSString
        for match in pattern.regex.matches(in: snapshot as String, range: NSRange(location: 0, length: snapshot.length)) {
            if body(match, snapshot) { consume(match.range) }
        }
    }

    mutating func consumeFirst(_ pattern: Pattern) -> NSRange? {
        let snapshot = masked as String
        guard let match = pattern.regex.firstMatch(
            in: snapshot, range: NSRange(location: 0, length: masked.length)
        ) else { return nil }
        consume(match.range)
        return match.range
    }

    private mutating func consume(_ range: NSRange) {
        masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        consumed.append(range)
    }

    /// Steht unmittelbar vor der Fundstelle ein Wort, das eine Frist anzeigt?
    static func isDeadline(before range: NSRange, in original: NSString) -> Bool {
        let start = max(0, range.location - 24)
        let lead = original.substring(with: NSRange(location: start, length: range.location - start))
        return Patterns.deadlineLead.matches(lead)
    }

    /// Der Text mit Platzhaltern an den Stellen der Zeitangaben.
    func remainder() -> String {
        let result = NSMutableString(string: original)
        for range in consumed.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: range, with: String(Scan.marker))
        }
        return result as String
    }
}

// MARK: - Muster

/// Ein uebersetzter regulaerer Ausdruck.
private final class Pattern: Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseSensitive: Bool = false) {
        // Die Muster stehen fest im Quelltext; ein Fehler darin ist ein
        // Programmierfehler und soll beim ersten Test auffallen.
        regex = try! NSRegularExpression(
            pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]
        )
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    func replace(in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }
}

private extension NSTextCheckingResult {
    func string(_ group: Int, in text: NSString) -> String? {
        guard group < numberOfRanges else { return nil }
        let range = self.range(at: group)
        return range.location == NSNotFound ? nil : text.substring(with: range)
    }

    func int(_ group: Int, in text: NSString) -> Int? {
        string(group, in: text).flatMap { Int($0) }
    }
}

private enum Patterns {
    private static let months = "januar|jänner|february|februar|january|märz|maerz|march|april|mai|may|juni|june|"
        + "juli|july|august|september|oktober|october|november|dezember|december|"
        + "jan|feb|mär|mrz|mar|apr|jun|jul|aug|sept|sep|okt|oct|nov|dez|dec"

    private static let weekdays = "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag|"
        + "monday|tuesday|wednesday|thursday|friday|saturday|sunday"

    /// Wochentag vor einem Datum: „Fr, 12.2." - gehoert zum Datum und
    /// verschwindet mit ihm.
    private static let weekdayPrefix = "(?:\\b(?:\(weekdays)|mo|di|mi|do|fr|sa|so)\\.?,?\\s+(?:den\\s+|dem\\s+)?)?"

    // Uhrzeiten

    /// 10:15–11:45
    static let rangeColon = Pattern(
        "(?<![\\d.:])(\\d{1,2}):(\\d{2})\\s*(?:uhr\\s*)?(?:-|–|—|bis)\\s*(\\d{1,2}):(\\d{2})(?!\\d)(?:\\s*uhr)?"
    )
    /// 13.15–14.45 Uhr - nur mit „Uhr", sonst waere „12.11.–14.11." eine Uhrzeit.
    static let rangeDotted = Pattern(
        "(?<![\\d.:])(\\d{1,2})\\.(\\d{2})\\s*(?:uhr\\s*)?(?:-|–|—|bis)\\s*(\\d{1,2})\\.(\\d{2})\\s*uhr"
    )
    /// von 13 bis 15 Uhr, 14–16 Uhr, 9 bis 10:30 Uhr
    static let rangeHours = Pattern(
        "(?:\\bvon\\s+)?(?<![\\d.:])(\\d{1,2})(?::(\\d{2}))?\\s*(?:uhr\\s*)?(?:-|–|—|bis)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*uhr"
    )
    /// 14:30
    static let timeColon = Pattern("(?<![\\d.:])(\\d{1,2}):(\\d{2})(?![\\d:])(?:\\s*uhr|\\s*h\\b)?")
    /// 14.30 Uhr
    static let timeDotted = Pattern("(?<![\\d.:])(\\d{1,2})\\.(\\d{2})\\s*uhr")
    /// 14 Uhr, 14 Uhr 30
    static let timeHour = Pattern("(?<![\\d.:])(\\d{1,2})\\s*uhr\\b(?:\\s*(\\d{2})(?![\\d.:]))?")
    /// 3 pm, 3:30 p.m.
    static let timePM = Pattern("(?<![\\d.:])(\\d{1,2})(?::(\\d{2}))?\\s*(?:pm|p\\.m\\.)(?![a-z])")
    /// 14h
    static let timeH = Pattern("(?<![\\d.:,])(\\d{1,2})\\s?h\\b")
    /// „Fr 14h", „Do, 18 Uhr" - Gross geschrieben, direkt vor einer Uhrzeit.
    /// „So" nur mit Punkt oder Komma, sonst waere jedes „So um 15 Uhr ..." ein
    /// Sonntag.
    static let weekdayBeforeTime = Pattern(
        "\\b(?:(Mo|Di|Mi|Do|Fr|Sa)[.,]?|(?:So)[.,])\\s+(?=(?:um\\s+)?\\d{1,2}(?::\\d{2}|\\.\\d{2}\\s*[Uu]hr|\\s*[Uu]hr|\\s?h\\b))",
        caseSensitive: true
    )
    /// um 14
    static let timeAtHour = Pattern("\\b(?:um|gegen)\\s+(\\d{1,2})(?![\\d.:])\\b")

    // Daten

    static let dateISO = Pattern("(?<![\\d-])(\\d{4})-(\\d{2})-(\\d{2})(?![\\d-])")
    /// 12.2., 12.02.2027, 12.2.27, 12.2. 2027
    static let dateNumeric = Pattern(
        weekdayPrefix + "(?<![\\d.])(\\d{1,2})\\.\\s?(\\d{1,2})\\.(?:(\\d{4}|\\d{2})(?![\\d:.])|\\s(\\d{4})(?!\\d))?"
    )
    /// „am 12.2" ohne Schlusspunkt - nur nach einem Verhaeltniswort.
    static let dateNumericShort = Pattern(
        "(?<=\\b(?:am|den|dem|vom|bis|zum|ab)\\s)(\\d{1,2})\\.(\\d{1,2})(?![\\d.:])"
    )
    /// 12/02/2027
    static let dateSlash = Pattern("(?<![\\d/])(\\d{1,2})/(\\d{1,2})/(\\d{4}|\\d{2})(?![\\d/])")
    /// 12. Februar 2027, 3 Dez
    static let dateDayMonth = Pattern(
        weekdayPrefix + "(?<![\\d.:])(\\d{1,2})\\.?\\s*(\(months))(?![a-zäöüß])\\.?(?:,?\\s+(\\d{4})(?!\\d))?"
    )
    /// February 12, 2027
    static let dateMonthDay = Pattern(
        "\\b(\(months))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?![\\d.:a-zäöüß])(?:,?\\s+(\\d{4})(?!\\d))?"
    )

    // Bezogenes

    static let nextWeek = Pattern("\\b(?:nächste|kommende|next)[rn]?\\s+(?:woche|week)\\b")
    static let weekday = Pattern(
        "\\b(?:(übernächsten?|nächsten?|kommenden?|diesen?|next|this|am|bis|ab|on)\\s+)?(\(weekdays))\\b"
    )
    /// „morgen" ist nur morgen, wenn es nicht „am Morgen", „guten Morgen" oder
    /// „morgens" heisst.
    static let relativeDay = Pattern(
        "(?<!\\bam\\s)(?<!\\bguten\\s)(?<!\\bjeden\\s)(?<!\\bden\\s)\\b(heute|übermorgen|morgen|today|tomorrow)\\b"
    )
    static let relativeSpan = Pattern(
        "\\bin\\s+(\\d{1,3}|einem|einer|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn)\\s+"
            + "(tagen|tag|days?|wochen?|weeks?|monaten|monat|months?)\\b"
    )
    static let duration = Pattern(
        "\\b(?:für|dauer:?|dauert|ca\\.?)\\s*(\\d{1,3}(?:[.,]\\d)?)\\s*(stunden?|std\\.?|h|minuten|min\\.?)(?![a-zäöüß])"
    )

    // Art

    static let deadlineLead = Pattern(
        "\\b(?:bis|spätestens|deadline|frist|fällig|abgabe)\\b:?\\s*(?:zum\\s+|am\\s+|spätestens\\s+|ist\\s+)?(?:\(weekdays)|mo|di|mi|do|fr|sa|so)?\\.?,?\\s*(?:den\\s+|dem\\s+)?$"
    )
    static let taskLabel = Pattern("^\\s*(?:[-*•–]\\s*)?(?:todo|to-do|to do|aufgabe|erledigen|\\[\\s?\\])\\b:?")
    static let eventLabel = Pattern("^\\s*(?:[-*•–]\\s*)?(?:termin|meeting|treffen)\\b:")
    static let taskVerb = Pattern(
        "\\b(?:abgabe|abgeben|einreichen|erledigen|anmelden|anmeldung|bezahlen|überweisen|kaufen|"
            + "einkaufen|besorgen|anrufen|schicken|senden|kündigen|buchen|bestellen|lernen|vorbereiten|"
            + "abholen|putzen|aufräumen|ausfüllen|beantragen|verlängern|zurückgeben|zurückschicken|"
            + "nicht vergessen|denk dran|melde dich)\\b"
    )
    static let greeting = Pattern(
        "^\\s*(?:hallo|hi|hey|guten\\s+(?:tag|morgen|abend)|liebe[rs]?|sehr geehrte[rs]?|"
            + "viele grüße|liebe grüße|beste grüße|mit freundlichen|freundliche grüße|"
            + "lg|vg|mfg|gruß|danke|vielen dank|dear|best regards|kind regards|thanks)\\b"
    )

    // Aufraeumen

    static let danglingBefore = Pattern(
        "\\b(?:am|um|ab|von|vom|bis|zum|zur|den|dem|on|at|gegen|spätestens|ca\\.?|und)\\s*(?=\\x01)"
    )
    static let danglingAfter = Pattern("\\x01\\s*(?:uhr|h)\\b")
    static let leadIn = Pattern(
        "^[\\s\\x01]*(?:[-*•–>]+\\s*|\\d{1,2}[.)]\\s+|\\[\\s?[x ]?\\s?\\]\\s*)?"
            + "(?:(?:hey|hi|hallo|moin|servus)\\b[^,!.:]{0,24}[,!]\\s*)?"
            + "(?:(?:todo|to-do|to do|aufgabe|termin|erinnerung|reminder|betreff|subject|re|aw|fwd?)\\s*:\\s*)*"
    )
    static let trailingFiller = Pattern("\\s+(?:statt|findet statt|ist|am|um|bis|von|ab|und)$")
    static let emptyBrackets = Pattern("[\\(\\[]\\s*[\\)\\]]")
    /// „Vortrag, , , Raum 12" -> „Vortrag, Raum 12"
    static let repeatedPunctuation = Pattern("(?:\\s*[,;:]){2,}")
    /// Trennstellen zwischen Teilsaetzen. Ein Komma nach einem Wochentag trennt
    /// nicht - „am Mittwoch, den 18.11." ist eine Angabe, nicht zwei.
    static let clauseBreak = Pattern(
        "(?<!\\b(?:\(weekdays)|mo|di|mi|do|fr|sa|so)),\\s+|;\\s+|\\s+(?:und|sowie|and)\\s+"
    )
    static let spaceBeforePunctuation = Pattern("\\s+([,;:.!?])")
    static let whitespace = Pattern("\\s+")
    /// Satzende: Punkt nach mindestens zwei Buchstaben, danach Grossbuchstabe.
    static let sentenceBreak = Pattern(
        "((?<=[a-zäöüß\\)]{2})[.!?]|;)\\s+(?=[A-ZÄÖÜ0-9])", caseSensitive: true
    )
}

// MARK: - Zusammenfuehren mit einem Sprachmodell

public extension QuickParser {

    /// Was ein Sprachmodell zu einem Eintrag beitraegt: wie er heisst, was er
    /// ist, und aus welcher Textstelle er stammt.
    struct Suggestion: Sendable, Hashable {
        public var kind: EntryDraft.Kind?
        public var title: String
        public var snippet: String

        public init(kind: EntryDraft.Kind?, title: String, snippet: String) {
            self.kind = kind
            self.title = title
            self.snippet = snippet
        }
    }

    /// Verbindet die eigenen Entwuerfe mit den Vorschlaegen eines Sprachmodells.
    ///
    /// Die Aufgabenteilung ist streng, und das mit Absicht:
    ///
    /// - **Wann** etwas ist, bestimmen allein die Regeln. Ein Modell, das den
    ///   12.2. ins falsche Jahr legt, soll das nicht duerfen.
    /// - **Was** es ist - Termin oder Aufgabe -, bestimmen bei datierten
    ///   Eintraegen ebenfalls die Regeln: Eine Uhrzeit macht den Termin, eine
    ///   Frist die Aufgabe.
    /// - **Wie es heisst**, sagt das Modell. Darin ist es gut: „Zahnreinigung"
    ///   statt „Ihr Termin zur Zahnreinigung ist".
    /// - Steht im Text **gar kein Datum**, zerlegt das Modell ihn in einzelne
    ///   Aufgaben - „Milch kaufen und den Brief einwerfen" sind zwei.
    ///
    /// Nichts, was das Modell nennt, wird ungeprueft uebernommen: Ein Titel,
    /// dessen Woerter im Text gar nicht vorkommen, ist erfunden und fliegt raus.
    static func refine(
        local: [EntryDraft],
        with suggestions: [Suggestion],
        text: String,
        today: DateKey
    ) -> [EntryDraft] {
        let hasDatedEntries = local.contains { $0.hasExplicitDate || $0.time != nil }

        // Was als belegt gilt, haengt davon ab, was auf dem Spiel steht:
        //
        // - Gliedert das Modell einen Text ohne Datum, entstehen aus seinen
        //   Titeln neue Eintraege. Dann muss der Titel selbst im Text stehen.
        // - Benennt es nur einen Eintrag, den die Regeln ohnehin gefunden haben,
        //   genuegt es, dass die Textstelle stimmt. „Anmeldung" fuer „melde
        //   dich an" ist eine gute Zusammenfassung, auch wenn das Wort so nicht
        //   dasteht.
        let grounded = suggestions.filter { suggestion in
            isGrounded(suggestion.title, in: text)
                || (hasDatedEntries && isGrounded(suggestion.snippet, in: text, share: 0.7))
        }
        guard !grounded.isEmpty else { return local }

        guard hasDatedEntries else {
            // Kein Datum im ganzen Text: Hier darf das Modell gliedern.
            let split = grounded.compactMap { suggestion -> EntryDraft? in
                let title = cleanTitle(suggestion.title)
                guard !title.isEmpty else { return nil }
                return EntryDraft(kind: suggestion.kind ?? .task, title: title, date: today,
                                  hasExplicitDate: false)
            }
            return split.isEmpty ? local : split
        }

        var result = local
        var used: Set<Int> = []

        for suggestion in grounded {
            guard let candidate = draft(kind: suggestion.kind, title: suggestion.title,
                                        snippet: suggestion.snippet, today: today),
                  let index = match(candidate, in: result, excluding: used)
            else { continue }

            used.insert(index)
            let title = cleanTitle(moment(in: suggestion.title, today: today).remainder)
            guard isSpecific(title) else { continue }
            result[index].title = title + suffix(of: result[index].title)
        }
        return result
    }

    /// Welcher eigene Entwurf gehoert zu diesem Vorschlag? Erst der mit
    /// gleichem Tag und gleicher Uhrzeit, dann der mit gleichem Tag, dann - wenn
    /// der Ausschnitt nur die Uhrzeit enthielt - der mit gleicher Uhrzeit.
    private static func match(_ candidate: EntryDraft, in drafts: [EntryDraft],
                              excluding used: Set<Int>) -> Int? {
        let free = drafts.indices.filter { !used.contains($0) }

        if candidate.hasExplicitDate {
            if let exact = free.first(where: {
                drafts[$0].date == candidate.date && drafts[$0].time == candidate.time
            }) { return exact }
            return free.first { drafts[$0].date == candidate.date }
        }
        if let time = candidate.time {
            return free.first { drafts[$0].time == time }
        }
        return nil
    }

    /// Der Zusatz, den die Regeln an den Titel gehaengt haben - „(bis 12:00)",
    /// „(bis 18.12.)". Er bleibt, wenn das Modell den Titel ersetzt.
    private static func suffix(of title: String) -> String {
        guard let range = title.range(of: " (bis ", options: .backwards), title.hasSuffix(")") else {
            return ""
        }
        return String(title[range.lowerBound...])
    }

    /// Stammt die Wendung aus dem Text? Ein ausreichender Anteil ihrer
    /// bedeutungstragenden Woerter muss dort stehen.
    ///
    /// Verglichen wird der Wortanfang, nicht das ganze Wort: „Klausuranmeldung"
    /// ist durch „Klausur" belegt, „anrufen" durch „anruf". Deutsche Woerter
    /// beugen und verbinden sich zu sehr fuer einen genauen Vergleich.
    static func isGrounded(_ phrase: String, in text: String, share: Double = 0.5) -> Bool {
        let haystack = text.lowercased()
        let words = phrase.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard !words.isEmpty else { return false }
        let found = words.filter { haystack.contains($0.prefix(5)) }.count
        return Double(found) >= Double(words.count) * share
    }

    /// Ein Titel, der mehr sagt als „Termin".
    private static func isSpecific(_ title: String) -> Bool {
        let generic: Set<String> = ["termin", "aufgabe", "eintrag", "ereignis", "todo", "meeting",
                                    "erinnerung", "treffen"]
        return title.count >= 3 && !generic.contains(title.lowercased())
    }
}

// MARK: - Antwort des Sprachmodells lesen

public extension QuickParser {

    /// Liest die Antwort eines Sprachmodells: ein JSON-Array mit `art`, `titel`
    /// und `ausschnitt`.
    ///
    /// Nachsichtig, weil Modelle es mit dem Format nicht genau nehmen: Text vor
    /// und nach dem Array wird uebergangen, ebenso die Umrandung eines
    /// Code-Blocks. Was sich nicht lesen laesst, ergibt `nil` - dann arbeiten
    /// die Regeln allein weiter.
    static func suggestions(fromModelOutput raw: String) -> [Suggestion]? {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let items = try? JSONDecoder().decode([ModelItem].self, from: data)
        else { return nil }

        return items.compactMap { item in
            let title = (item.titel ?? item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let kind: EntryDraft.Kind?
            switch (item.art ?? item.type ?? "").lowercased() {
            case "termin", "event": kind = .event
            case "aufgabe", "task", "todo": kind = .task
            default: kind = nil
            }
            return Suggestion(kind: kind, title: title, snippet: item.ausschnitt ?? item.snippet ?? title)
        }
    }

    private struct ModelItem: Decodable {
        var art: String?
        var type: String?
        var titel: String?
        var title: String?
        var ausschnitt: String?
        var snippet: String?
    }
}
