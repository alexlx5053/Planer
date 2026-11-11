import PlanerCore
import PlanerData
import SwiftUI
import WidgetKit

// MARK: - Daten

/// Was das Widget anzeigt.
struct PlanerEntry: TimelineEntry {
    let date: Date
    let done: Int
    let total: Int
    let streak: Int
    let upcoming: [UpcomingEvent]
    /// Konnte die Datei nicht gelesen werden? Dann sagt das Widget das, statt
    /// stillschweigend Nullen zu zeigen.
    let couldRead: Bool

    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var isPerfect: Bool { total > 0 && done == total }

    static let placeholder = PlanerEntry(
        date: .now, done: 3, total: 5, streak: 4,
        upcoming: [], couldRead: true
    )
}

/// Liest den Bestand direkt aus der Datei der App.
///
/// Der uebliche Weg waere eine geteilte App-Gruppe - die setzt allerdings ein
/// Apple-Developer-Konto voraus. Da die App nicht in der Sandbox laeuft, genuegt
/// der direkte Pfad.
enum WidgetData {

    static func load(now: Date = Date()) -> PlanerEntry {
        let today = DateKey(now)

        guard let data = try? Data(contentsOf: StoreLocation.applicationSupport.file),
              let document = try? StoredDocument.decoder.decode(StoredDocument.self, from: data)
        else {
            return PlanerEntry(date: now, done: 0, total: 0, streak: 0,
                               upcoming: [], couldRead: false)
        }

        let state = document.state
        let stats = state.stats(for: today, today: today)

        return PlanerEntry(
            date: now,
            done: stats.completedTotal,
            total: stats.itemTotal,
            streak: state.currentStreak(today: today),
            upcoming: state.upcomingEvents(from: today, limit: 3),
            couldRead: true
        )
    }
}

struct PlanerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanerEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PlanerEntry) -> Void) {
        completion(WidgetData.load())
    }

    /// Alle 15 Minuten neu, spaetestens aber um Mitternacht - dann wechselt der
    /// Tag und alle Zahlen stimmen nicht mehr.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanerEntry>) -> Void) {
        let now = Date()
        let entry = WidgetData.load(now: now)

        let nextQuarter = now.addingTimeInterval(15 * 60)
        let midnight = ldCalendar.startOfDay(for: now.addingTimeInterval(86_400))
        let refresh = min(nextQuarter, midnight)

        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Darstellung

struct PlanerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanerEntry

    private let ink = Color(white: 0.93)
    private let muted = Color(white: 0.56)
    private let faint = Color(white: 0.35)

    var body: some View {
        Group {
            if !entry.couldRead {
                Text("Keine Daten gefunden")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .containerBackground(.black, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            ring(diameter: 58, lineWidth: 5)

            Spacer(minLength: 0)

            if let next = entry.upcoming.first {
                Text(next.event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(next.longLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            } else {
                Text("Nichts in Sicht")
                    .font(.system(size: 11))
                    .foregroundStyle(faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ring(diameter: 66, lineWidth: 5)
                if entry.streak > 0 {
                    Text("\(entry.streak) Tage in Folge")
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Nächste Termine")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(muted)

                if entry.upcoming.isEmpty {
                    Text("Nichts in Sicht")
                        .font(.system(size: 11))
                        .foregroundStyle(faint)
                } else {
                    ForEach(entry.upcoming) { item in
                        HStack(spacing: 6) {
                            Text(item.event.title)
                                .font(.system(size: 12, weight: item.daysAway <= 1 ? .medium : .regular))
                                .foregroundStyle(item.daysAway <= 1 ? ink : muted)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.shortLabel)
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(item.daysAway <= 1 ? ink : faint)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ring(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color(white: 0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, entry.fraction)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(entry.fraction > 0 ? 1 : 0)

            VStack(spacing: 0) {
                Text("\(Int((entry.fraction * 100).rounded()))")
                    .font(.system(size: diameter * 0.30, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(size: diameter * 0.15))
                    .monospacedDigit()
                    .foregroundStyle(faint)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Einstieg

struct PlanerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.alexlx5053.planer.heute", provider: PlanerProvider()) { entry in
            PlanerWidgetView(entry: entry)
        }
        .configurationDisplayName("Heute")
        .description("Tagesfortschritt und die nächsten Termine.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PlanerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanerWidget()
    }
}
