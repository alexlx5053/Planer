import SwiftUI

/// Der kurze Funkenflug beim Abhaken. (Spezifikation 4.7)
///
/// Monochrom gehalten: Auf schwarzem Grund traegt Helligkeit, und bunte Schnipsel
/// wuerden aus dem Bild fallen. Gezeichnet wird in einem `Canvas` mit
/// `TimelineView` - so laeuft die Bewegung auf 120 Hz und blockiert nichts.
struct ConfettiBurst: View {
    /// Zeitpunkt des Abhakens - der Flug rechnet sich daraus.
    let start: Date

    private let duration: Double = 0.55
    private let particles: [Particle]

    init(start: Date) {
        self.start = start
        var generator = SystemRandomNumberGenerator()
        particles = (0..<12).map { index in
            Particle(
                angle: Double(index) / 12 * 2 * .pi + Double.random(in: -0.2...0.2, using: &generator),
                distance: Double.random(in: 12...26, using: &generator),
                size: Double.random(in: 1.4...2.8, using: &generator),
                brightness: Double.random(in: 0.55...1.0, using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < duration else { return }
                let progress = elapsed / duration
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in particles {
                    // Schnell heraus, dann auslaufen - und ein wenig Schwerkraft,
                    // damit es faellt statt zu schweben.
                    let eased = 1 - pow(1 - progress, 2.2)
                    let distance = particle.distance * eased
                    let drop = 10 * progress * progress

                    let point = CGPoint(
                        x: center.x + cos(particle.angle) * distance,
                        y: center.y + sin(particle.angle) * distance + drop
                    )
                    let radius = particle.size * (1 - progress * 0.5)
                    let rect = CGRect(
                        x: point.x - radius, y: point.y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(particle.brightness * (1 - progress)))
                    )
                }
            }
        }
        .frame(width: 64, height: 64)
        .allowsHitTesting(false)
    }

    private struct Particle {
        let angle: Double
        let distance: Double
        let size: Double
        let brightness: Double
    }
}
