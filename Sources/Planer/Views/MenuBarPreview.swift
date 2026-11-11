import SwiftUI

/// Zeigt das Menueleisten-Symbol in mehreren Fuellstaenden nebeneinander.
///
/// In der echten Menueleiste ist es 18 Punkt gross - hier vergroessert, damit
/// sich die Form beurteilen laesst.
struct MenuBarIconPreview: View {
    private let steps: [(Double, Bool, String)] = [
        (0, false, "leer"), (0.25, false, "25 %"), (0.5, false, "50 %"),
        (0.75, false, "75 %"), (1, true, "perfekt"),
    ]

    var body: some View {
        VStack(spacing: Metrics.spacing20) {
            HStack(spacing: Metrics.spacing24) {
                ForEach(steps, id: \.2) { fraction, perfect, label in
                    VStack(spacing: Metrics.spacing8) {
                        Image(nsImage: MenuBarIcon.image(fraction: fraction, isPerfect: perfect))
                            .renderingMode(.template)
                            .foregroundStyle(Palette.textPrimary)
                            .scaleEffect(3)
                            .frame(width: 54, height: 54)
                        Text(label)
                            .font(Typo.chip)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }

            Text("In der Menüleiste erscheinen sie in 18 Punkt Größe.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Metrics.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}
