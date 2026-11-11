import Foundation
import Testing
@testable import PlanerCore

/// Der Leser, der aus freiem Text Termine und Aufgaben macht.
@Suite("Aus Text lesen")
struct QuickParserTests {

    /// Dienstag, 10.11.2026.
    private let today = DateKey(year: 2026, month: 11, day: 10)

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private func time(_ raw: String) -> ClockTime { ClockTime(raw)! }

    private func moment(_ text: String) -> QuickParser.Moment {
        QuickParser.moment(in: text, today: today)
    }

    private func one(_ text: String) -> EntryDraft {
        let drafts = QuickParser.drafts(from: text, today: today)
        #expect(drafts.count == 1, "erwartet: genau ein Entwurf für „\(text)“, gefunden \(drafts.count)")
        return drafts.first ?? EntryDraft(kind: .task, title: "", date: today)
    }

    // MARK: - Datum

    @Test func numericDates() {
        #expect(moment("am 12.11. Zahnarzt").date == day("2026-11-12"))
        #expect(moment("12.02.2027").date == day("2027-02-12"))
        #expect(moment("12.2.27").date == day("2027-02-12"))
        #expect(moment("2027-02-12 Klausur").date == day("2027-02-12"))
        #expect(moment("am 3.12 Treffen").date == day("2026-12-03"))
        #expect(moment("12/02/2027").date == day("2027-02-12"))
    }

    /// Der Fehler, den das Sprachmodell gemacht hat: Ohne Jahr ist der naechste
    /// 12.2. gemeint, nicht der vergangene.
    @Test func missingYearMeansTheNextOccurrence() {
        #expect(moment("Klausur am 12.2.").date == day("2027-02-12"))
        #expect(moment("am 30.11.").date == day("2026-11-30"))
        // Heute selbst zaehlt noch als dieses Jahr.
        #expect(moment("10.11.").date == day("2026-11-10"))
        #expect(moment("9.11.").date == day("2027-11-09"))
    }

    @Test func writtenMonths() {
        #expect(moment("12. Februar").date == day("2027-02-12"))
        #expect(moment("3. Dez. 2026").date == day("2026-12-03"))
        #expect(moment("am 5 März 2027").date == day("2027-03-05"))
        #expect(moment("Montag, 16. November").date == day("2026-11-16"))
        #expect(moment("February 12, 2027").date == day("2027-02-12"))
        #expect(moment("Dec 3").date == day("2026-12-03"))
    }

    @Test func impossibleDatesAreNotDates() {
        #expect(moment("31.2.").date == nil)
        #expect(moment("45.13.").date == nil)
        // Versionsnummern und Kommazahlen sind keine Daten.
        #expect(moment("Version 3.5 testen").date == nil)
        #expect(moment("3 Mails schreiben").date == nil)
    }

    @Test func relativeDays() {
        #expect(moment("heute Abend").date == today)
        #expect(moment("morgen Zahnarzt").date == day("2026-11-11"))
        #expect(moment("Morgen 10 Uhr Meeting").date == day("2026-11-11"))
        #expect(moment("übermorgen").date == day("2026-11-12"))
        #expect(moment("in 3 Tagen").date == day("2026-11-13"))
        #expect(moment("in zwei Wochen").date == day("2026-11-24"))
        #expect(moment("in einem Monat").date == day("2026-12-10"))
    }

    @Test func morgenIsNotAlwaysTomorrow() {
        #expect(moment("am Morgen laufen").date == nil)
        #expect(moment("Guten Morgen zusammen").date == nil)
        #expect(moment("morgens Vitamine nehmen").date == nil)
    }

    /// Der zweite Fehler des Sprachmodells: „bis Freitag" war bei ihm ein
    /// Samstag.
    @Test func weekdays() {
        #expect(moment("am Freitag").date == day("2026-11-13"))
        #expect(moment("bis Freitag").date == day("2026-11-13"))
        #expect(moment("nächsten Montag").date == day("2026-11-16"))
        // Heute ist Dienstag - „am Dienstag" meint den naechsten.
        #expect(moment("am Dienstag").date == day("2026-11-17"))
        #expect(moment("übernächsten Freitag").date == day("2026-11-20"))
        #expect(moment("nächste Woche Mittwoch").date == day("2026-11-18"))
        #expect(moment("nächste Woche").date == day("2026-11-16"))
        // „montags" ist eine Gewohnheit, kein Datum.
        #expect(moment("montags Sport").date == nil)
    }

    @Test func explicitDateBeatsTheWeekdayNextToIt() {
        // Der 12.2.2027 ist ein Freitag; selbst wenn der Wochentag falsch
        // dastuende, gilt das Datum.
        #expect(moment("Freitag, 12.2.").date == day("2027-02-12"))
        #expect(moment("Fr 13.11. Abgabe").date == day("2026-11-13"))
    }

    // MARK: - Uhrzeit

    @Test func singleTimes() {
        #expect(moment("um 14:30").time == time("14:30"))
        #expect(moment("14.30 Uhr").time == time("14:30"))
        #expect(moment("14 Uhr").time == time("14:00"))
        #expect(moment("um 9").time == time("09:00"))
        #expect(moment("8 Uhr 15").time == time("08:15"))
        #expect(moment("3 pm").time == time("15:00"))
        #expect(moment("gegen 18 Uhr").time == time("18:00"))
    }

    /// Der dritte Fehler des Sprachmodells: 10:15–11:45 waren bei ihm
    /// 39 Minuten.
    @Test func timeRangesGiveADuration() {
        let range = moment("von 10:15 bis 11:45")
        #expect(range.time == time("10:15"))
        #expect(range.durationMinutes == 90)

        #expect(moment("10:15–11:45").durationMinutes == 90)
        #expect(moment("10:15 - 11:45 Uhr").durationMinutes == 90)
        #expect(moment("von 13 bis 15 Uhr").durationMinutes == 120)
        #expect(moment("14-16 Uhr").time == time("14:00"))
        #expect(moment("9 bis 10:30 Uhr").durationMinutes == 90)
        #expect(moment("10.15 bis 11.45 Uhr").durationMinutes == 90)
    }

    @Test func explicitDuration() {
        let found = moment("Lerngruppe um 16 Uhr für 2 Stunden")
        #expect(found.time == time("16:00"))
        #expect(found.durationMinutes == 120)
        #expect(moment("Call 10:00, Dauer: 45 Min").durationMinutes == 45)
    }

    @Test func dateAndTimeDoNotGetMixedUp() {
        let found = moment("am 13.11. um 14.30 Uhr")
        #expect(found.date == day("2026-11-13"))
        #expect(found.time == time("14:30"))

        // Ein Datumsbereich ist keine Uhrzeit.
        let range = moment("12.11.-14.11. Konferenz")
        #expect(range.time == nil)
        #expect(range.date == day("2026-11-12"))

        // „12.2. 14 Uhr": die 14 ist kein Jahr.
        let compact = moment("12.2. 14 Uhr")
        #expect(compact.date == day("2027-02-12"))
        #expect(compact.time == time("14:00"))
    }

    // MARK: - Ganze Entwuerfe

    @Test func appointmentWithDateAndTime() {
        let draft = one("Zahnarzt am 12.11. um 14:30")
        #expect(draft.kind == .event)
        #expect(draft.title == "Zahnarzt")
        #expect(draft.date == day("2026-11-12"))
        #expect(draft.time == time("14:30"))
    }

    @Test func leadingDateIsRemovedFromTheTitle() {
        let draft = one("Am 12.2. von 10:15 bis 11:45 Klausur Statistik")
        #expect(draft.title == "Klausur Statistik")
        #expect(draft.kind == .event)
        #expect(draft.durationMinutes == 90)
        #expect(draft.span?.text == "10:15–11:45")
    }

    @Test func compactNotation() {
        let draft = one("Morgen 10 Uhr Meeting mit Tim")
        #expect(draft.title == "Meeting mit Tim")
        #expect(draft.date == day("2026-11-11"))
        #expect(draft.time == time("10:00"))
    }

    @Test func dateWithoutTimeIsAnAllDayAppointment() {
        let draft = one("Geburtstag Anna 3. Dezember")
        #expect(draft.kind == .event)
        #expect(draft.time == nil)
        #expect(draft.title == "Geburtstag Anna")
    }

    @Test func deadlinesAreTasks() {
        let draft = one("Hausarbeit abgeben bis 15.12.")
        #expect(draft.kind == .task)
        #expect(draft.title == "Hausarbeit abgeben")
        #expect(draft.date == day("2026-12-15"))

        #expect(one("Bitte melde dich bis Freitag dafür an").kind == .task)
        #expect(one("Deadline: 20.11. Bewerbung").kind == .task)
    }

    @Test func deadlineKeepsItsTimeInTheTitle() {
        let draft = one("Abgabe Präsentation bis Freitag 12 Uhr")
        #expect(draft.kind == .task)
        #expect(draft.time == nil)
        #expect(draft.title.contains("bis 12:00"))
        #expect(draft.date == day("2026-11-13"))
    }

    @Test func taskVerbsMakeTasks() {
        #expect(one("Milch kaufen morgen").kind == .task)
        #expect(one("TODO: Vertrag kündigen am 30.11.").kind == .task)
        #expect(one("TODO: Vertrag kündigen am 30.11.").title == "Vertrag kündigen")
    }

    @Test func textWithoutAnyDateBecomesTasksForToday() {
        let drafts = QuickParser.drafts(from: "- Milch kaufen\n- Brief einwerfen\n• Steuer machen", today: today)
        #expect(drafts.map(\.title) == ["Milch kaufen", "Brief einwerfen", "Steuer machen"])
        #expect(drafts.allSatisfy { $0.kind == .task && $0.date == today && !$0.hasExplicitDate })
    }

    @Test func durationInATaskTitleStaysInTheTitle() {
        // Deine eigene Schreibweise - daraus darf kein „lesen" werden.
        #expect(one("30 Minuten lesen").title == "30 Minuten lesen")
    }

    // MARK: - Mehrere auf einmal

    @Test func oneEntryPerLine() {
        let text = """
        Mathe Klausur 12.02.2027 10:15-11:45
        Physik Klausur 15.02.2027 09:00-10:30
        Englisch Test 3.3.
        """
        let drafts = QuickParser.drafts(from: text, today: today)
        #expect(drafts.map(\.title) == ["Mathe Klausur", "Physik Klausur", "Englisch Test"])
        #expect(drafts.map(\.date) == [day("2027-02-12"), day("2027-02-15"), day("2027-03-03")])
        #expect(drafts[0].durationMinutes == 90)
        #expect(drafts[2].time == nil)
    }

    @Test func sentencesInAMailAreSeparated() {
        let text = "Hallo Kim, die Klausur findet am 12.2. von 10:15 bis 11:45 in Raum 204 statt. "
            + "Bitte melde dich bis Freitag dafür an. Viele Grüße"
        let drafts = QuickParser.drafts(from: text, today: today)

        #expect(drafts.count == 2)
        #expect(drafts[0].kind == .event)
        #expect(drafts[0].date == day("2027-02-12"))
        #expect(drafts[0].durationMinutes == 90)
        #expect(drafts[1].kind == .task)
        #expect(drafts[1].date == day("2026-11-13"))
    }

    @Test func aDateHeadingAppliesToTheLinesBelow() {
        let text = """
        Montag, 16.11.
        10:00 Vorlesung
        14:30 Gruppenarbeit
        """
        let drafts = QuickParser.drafts(from: text, today: today)
        #expect(drafts.map(\.title) == ["Vorlesung", "Gruppenarbeit"])
        #expect(drafts.allSatisfy { $0.date == day("2026-11-16") })
        #expect(drafts.map(\.time) == [time("10:00"), time("14:30")])
    }

    @Test func aFollowUpSentenceBecomesTheNote() {
        let text = "Sprechstunde am 18.11. um 11 Uhr. Raum 2.04, bitte Unterlagen mitbringen."
        let draft = one(text)
        #expect(draft.title == "Sprechstunde")
        #expect(draft.notes.contains("2.04"))
    }

    @Test func sentenceSplittingRespectsDatesAndAbbreviations() {
        #expect(QuickParser.sentences(in: "Am 12.2. ist Klausur. Danach frei.").count == 2)
        #expect(QuickParser.sentences(in: "Treffen am 3.12. um 14 Uhr").count == 1)
    }

    // MARK: - Unordentliches aus Mails und Chats

    @Test func greetingIsNotPartOfTheTitle() {
        let draft = one("Hey, lass uns am Donnerstag um 18 Uhr im Café Central treffen")
        #expect(draft.title == "Lass uns im Café Central treffen")
        #expect(draft.date == day("2026-11-12"))
    }

    @Test func abbreviatedWeekdayBeforeATime() {
        let draft = one("Friseur Fr 14h")
        #expect(draft.title == "Friseur")
        #expect(draft.date == day("2026-11-13"))
        #expect(draft.time == time("14:00"))
        // „So" allein ist ein Wort, kein Sonntag.
        #expect(one("So um 15 Uhr geht es los").date == today)
        // Und „2h" ist eine Dauer, keine Uhrzeit.
        #expect(one("Lernen 2h").time == nil)
    }

    @Test func commasAroundRemovedDatesCollapse() {
        let draft = one("Gastvortrag, Mo 30.11., 17:00-18:30, Raum 12")
        #expect(draft.title == "Gastvortrag, Raum 12")
        #expect(draft.durationMinutes == 90)
    }

    @Test func twoDatedThingsInOneSentenceAreTwoEntries() {
        let drafts = QuickParser.drafts(
            from: "Flug nach Madrid 3. März 2027 06:40, Rückflug 10. März 2027 21:15", today: today
        )
        #expect(drafts.map(\.title) == ["Flug nach Madrid", "Rückflug"])
        #expect(drafts.map(\.date) == [day("2027-03-03"), day("2027-03-10")])
        // Ein „und" zwischen Namen trennt dagegen nichts.
        #expect(one("Essen mit Mama und Papa am Samstag, 19 Uhr").title == "Essen mit Mama und Papa")
    }

    @Test func secondDateWithoutNameInheritsTheFirst() {
        let drafts = QuickParser.drafts(
            from: "Lerngruppe am 20.11. um 9 Uhr und am 27.11. um 10 Uhr", today: today
        )
        #expect(drafts.map(\.title) == ["Lerngruppe", "Lerngruppe"])
        #expect(drafts.map(\.time) == [time("09:00"), time("10:00")])
    }

    @Test func aPeriodKeepsItsEnd() {
        let draft = one("Kursanmeldung: 7.12. – 18.12.2026")
        #expect(draft.date == day("2026-12-07"))
        #expect(draft.title == "Kursanmeldung (bis 18.12.)")
    }

    @Test func undatedLineUnderADateHeadingIsItsOwnEntry() {
        let drafts = QuickParser.drafts(
            from: "Dienstag 24.11.\n15:00–17:00 Referat\nMittwoch 25.11.\nVokabeln lernen",
            today: today
        )
        #expect(drafts.count == 2)
        #expect(drafts[1].kind == .task)
        #expect(drafts[1].date == day("2026-11-25"))
        #expect(drafts[0].notes.isEmpty)
    }

    @Test func aLetterFromThePractice() {
        let text = """
        Sehr geehrter Herr Beispiel,
        Ihr Termin zur Zahnreinigung ist am Mittwoch, den 18.11.2026 um 08:30 Uhr.
        Bitte bringen Sie Ihre Versichertenkarte mit.
        Mit freundlichen Grüßen
        """
        let draft = one(text)
        #expect(draft.date == day("2026-11-18"))
        #expect(draft.time == time("08:30"))
        #expect(draft.notes.contains("Versichertenkarte"))
        #expect(!draft.notes.contains("Grüßen"))
    }

    @Test func emptyTextGivesNothing() {
        #expect(QuickParser.drafts(from: "", today: today).isEmpty)
        #expect(QuickParser.drafts(from: "   \n \n", today: today).isEmpty)
        #expect(QuickParser.drafts(from: "Hallo!\nViele Grüße", today: today).isEmpty)
    }

    // MARK: - Mit Vorgaben vom Sprachmodell

    /// Das Modell liefert Art und Titel, das Wann wird aus dem Ausschnitt
    /// gerechnet - nie vom Modell uebernommen.
    @Test func modelTitleWithLocallyComputedDate() {
        let draft = QuickParser.draft(
            kind: .event,
            title: "Klausur Statistik",
            snippet: "die Klausur in Statistik findet am 12.2. von 10:15 bis 11:45 in Raum 204 statt",
            today: today
        )
        #expect(draft?.title == "Klausur Statistik")
        #expect(draft?.date == day("2027-02-12"))
        #expect(draft?.time == time("10:15"))
        #expect(draft?.durationMinutes == 90)
    }

    @Test func modelTitleLosesStrayDates() {
        let draft = QuickParser.draft(kind: .task, title: "Anmeldung bis Freitag",
                                      snippet: "Bitte melde dich bis Freitag dafür an", today: today)
        #expect(draft?.title == "Anmeldung")
        #expect(draft?.kind == .task)
        #expect(draft?.date == day("2026-11-13"))
    }

    @Test func draftsTurnIntoRealEntries() {
        let event = one("Zahnarzt am 12.11. um 14:30").makeEvent()
        #expect(event.title == "Zahnarzt")
        #expect(event.time == "14:30")
        #expect(event.startDate == day("2026-11-12"))

        let task = one("Hausarbeit abgeben bis 15.12.").makeTask()
        #expect(task.title == "Hausarbeit abgeben")
        #expect(task.startDate == day("2026-12-15"))
    }
}

/// Zusammenfuehren der eigenen Entwuerfe mit den Vorschlaegen eines Modells.
@Suite("Vorschlaege des Sprachmodells")
struct QuickParserRefineTests {

    private let today = DateKey(year: 2026, month: 11, day: 10)
    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    private func refine(_ text: String, _ suggestions: [QuickParser.Suggestion]) -> [EntryDraft] {
        QuickParser.refine(
            local: QuickParser.drafts(from: text, today: today),
            with: suggestions, text: text, today: today
        )
    }

    @Test func modelNamesRulesDate() {
        let text = "Hallo Kim, die Klausur in Statistik findet am 12.2. von 10:15 "
            + "bis 11:45 in Raum 204 statt. Bitte melde dich bis Freitag dafür an."
        let drafts = refine(text, [
            .init(kind: .event, title: "Klausur Statistik",
                  snippet: "die Klausur in Statistik findet am 12.2. von 10:15 bis 11:45 in Raum 204 statt"),
            .init(kind: .task, title: "Anmeldung", snippet: "Bitte melde dich bis Freitag dafür an"),
        ])

        #expect(drafts.map(\.title) == ["Klausur Statistik", "Anmeldung"])
        // Das Wann kommt aus den Regeln: richtiges Jahr, richtige Dauer,
        // richtiger Freitag.
        #expect(drafts[0].date == day("2027-02-12"))
        #expect(drafts[0].durationMinutes == 90)
        #expect(drafts[1].date == day("2026-11-13"))
        #expect(drafts[1].kind == .task)
    }

    /// Das Modell hielt die Klausur fuer eine Aufgabe. Ein Eintrag mit Datum
    /// und ohne Frist bleibt ein Termin.
    @Test func modelCannotChangeTheKindOfADatedEntry() {
        let drafts = refine("Englisch Test 3.3.", [
            .init(kind: .task, title: "Englisch Test", snippet: "Englisch Test 3.3."),
        ])
        #expect(drafts.count == 1)
        #expect(drafts[0].kind == .event)
        #expect(drafts[0].date == day("2027-03-03"))
    }

    @Test func modelCannotInventEntries() {
        let drafts = refine("Zahnarzt am 12.11. um 14:30", [
            .init(kind: .event, title: "Zahnarzt", snippet: "Zahnarzt am 12.11. um 14:30"),
            .init(kind: .event, title: "Geburtstagsfeier bei Tim", snippet: "am 20.11. um 20 Uhr"),
        ])
        #expect(drafts.count == 1)
        #expect(drafts[0].title == "Zahnarzt")
    }

    @Test func modelCannotMoveADate() {
        // Der Ausschnitt nennt ein anderes Datum als der Text - dann gibt es
        // keinen passenden Entwurf, und der Vorschlag verfaellt.
        let drafts = refine("Zahnarzt am 12.11. um 14:30", [
            .init(kind: .event, title: "Zahnarzt Kontrolle", snippet: "Zahnarzt am 13.12. um 9:00"),
        ])
        #expect(drafts.count == 1)
        #expect(drafts[0].date == day("2026-11-12"))
        #expect(drafts[0].title == "Zahnarzt")
    }

    @Test func modelSplitsUndatedText() {
        let text = "Ich muss noch Milch kaufen und den Brief einwerfen, außerdem Oma anrufen"
        let drafts = refine(text, [
            .init(kind: .task, title: "Milch kaufen", snippet: "Ich muss noch Milch kaufen"),
            .init(kind: .task, title: "Brief einwerfen", snippet: "und den Brief einwerfen"),
            // Der Ausschnitt ist nicht woertlich - der Titel steht aber im Text.
            .init(kind: .task, title: "Oma anrufen", snippet: "auch Oma anrufen"),
        ])
        #expect(drafts.map(\.title) == ["Milch kaufen", "Brief einwerfen", "Oma anrufen"])
        #expect(drafts.allSatisfy { $0.kind == .task && $0.date == today })
    }

    @Test func titlesNotFoundInTheTextAreDropped() {
        let text = "Milch kaufen"
        let drafts = refine(text, [
            .init(kind: .task, title: "Steuererklärung abgeben", snippet: "Milch kaufen"),
        ])
        // Erfunden - es bleibt beim eigenen Entwurf.
        #expect(drafts.map(\.title) == ["Milch kaufen"])
    }

    @Test func genericTitlesDoNotReplaceGoodOnes() {
        let drafts = refine("Zahnarzt am 12.11. um 14:30", [
            .init(kind: .event, title: "Termin", snippet: "Zahnarzt am 12.11. um 14:30"),
        ])
        #expect(drafts[0].title == "Zahnarzt")
    }

    @Test func deadlineSuffixSurvivesTheNewTitle() {
        let text = "Reminder: Abgabe der Präsentation Marketing bis spätestens 9.12.2026, 23:59 Uhr über das Lernportal."
        let drafts = refine(text, [
            .init(kind: .task, title: "Abgabe Präsentation Marketing", snippet: text),
        ])
        #expect(drafts.count == 1)
        #expect(drafts[0].kind == .task)
        #expect(drafts[0].title == "Abgabe Präsentation Marketing (bis 23:59)")
    }

    @Test func twoEntriesInTheSameSlotKeepTheirOwnNames() {
        let text = "Mathe Klausur 12.02.2027 10:15-11:45\nPhysik Klausur 12.02.2027 10:15-11:45"
        let drafts = refine(text, [
            .init(kind: .event, title: "Mathe Klausur", snippet: "Mathe Klausur 12.02.2027 10:15-11:45"),
            .init(kind: .event, title: "Physik Klausur",
                  snippet: "Physik Klausur 12.02.2027 10:15-11:45"),
        ])
        #expect(drafts.map(\.title) == ["Mathe Klausur", "Physik Klausur"])
    }

    @Test func noSuggestionsLeaveEverythingAsItWas() {
        #expect(refine("Zahnarzt am 12.11. um 14:30", []).map(\.title) == ["Zahnarzt"])
    }

    // MARK: - Antwort lesen

    @Test func readsTheModelsAnswer() {
        let raw = """
        ```json
        [
          {"art": "termin", "titel": "Zahnreinigung", "ausschnitt": "am 18.11. um 08:30 Uhr"},
          {"art": "aufgabe", "titel": "Anmeldung", "ausschnitt": "bis Freitag"}
        ]
        ```
        """
        let suggestions = QuickParser.suggestions(fromModelOutput: raw)
        #expect(suggestions?.map(\.title) == ["Zahnreinigung", "Anmeldung"])
        #expect(suggestions?.map(\.kind) == [.event, .task])
    }

    @Test func unreadableAnswersGiveNil() {
        #expect(QuickParser.suggestions(fromModelOutput: "Das kann ich leider nicht.") == nil)
        #expect(QuickParser.suggestions(fromModelOutput: "[{kaputt") == nil)
        #expect(QuickParser.suggestions(fromModelOutput: "[]")?.isEmpty == true)
        // Eintraege ohne Titel fallen weg, der Rest bleibt.
        let partial = QuickParser.suggestions(fromModelOutput: #"[{"art":"termin"},{"titel":"Kino"}]"#)
        #expect(partial?.map(\.title) == ["Kino"])
    }
}
