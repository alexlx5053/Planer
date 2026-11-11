import AppKit
import SwiftUI

/// Das Symbol in der Menueleiste: ein Ring, der den Tagesfortschritt zeigt.
///
/// Gezeichnet statt aus SF Symbols zusammengesetzt, weil es keinen Ring gibt,
/// der sich stufenlos fuellen laesst. Als Schablonenbild ueberlaesst es die
/// Farbe dem System - so passt es sich heller und dunkler Menueleiste an und
/// wird beim Anklicken korrekt invertiert, genau wie Batterie und Uhr.
enum MenuBarIcon {

    static func image(fraction: Double, isPerfect: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            let inset: CGFloat = 2
            let lineWidth: CGFloat = 2
            let box = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: box.midX, y: box.midY)
            let radius = box.width / 2 - lineWidth / 2

            // Die Bahn bleibt blass, der Fortschritt steht voll da. Bei einer
            // Schablone traegt allein die Deckkraft die Unterscheidung.
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if isPerfect {
                let filled = NSBezierPath()
                filled.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                filled.lineWidth = lineWidth
                NSColor.black.setStroke()
                filled.stroke()

                let check = NSBezierPath()
                check.move(to: NSPoint(x: center.x - radius * 0.45, y: center.y + radius * 0.03))
                check.line(to: NSPoint(x: center.x - radius * 0.12, y: center.y - radius * 0.34))
                check.line(to: NSPoint(x: center.x + radius * 0.48, y: center.y + radius * 0.38))
                check.lineWidth = lineWidth * 0.9
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.black.setStroke()
                check.stroke()
            } else if fraction > 0 {
                // Bei zwoelf Uhr beginnen und im Uhrzeigersinn laufen - so, wie
                // man eine Fuellstandsanzeige liest.
                let progress = NSBezierPath()
                progress.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * min(1, max(0, fraction)),
                    clockwise: true
                )
                progress.lineWidth = lineWidth
                progress.lineCapStyle = .round
                NSColor.black.setStroke()
                progress.stroke()
            }
            return true
        }

        image.isTemplate = true
        return image
    }
}
