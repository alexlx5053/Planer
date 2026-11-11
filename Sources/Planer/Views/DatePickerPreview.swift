import PlanerCore
import SwiftUI

/// Zeigt den aufklappbaren Kalender allein - im Fenster liegt er sonst ueber
/// dem Blatt und laesst sich nicht abziehen.
struct DatePickerPreview: View {
    @State private var date = DateKey(year: 2026, month: 9, day: 4)
    @State private var month = DateKey(year: 2026, month: 9, day: 4)
    @State private var isOpen = true

    var body: some View {
        CalendarPopover(date: $date, visibleMonth: $month, isOpen: $isOpen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
    }
}
