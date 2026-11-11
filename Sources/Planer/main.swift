import AppKit
import Foundation

// Einstiegspunkt. Normalerweise startet die SwiftUI-App; mit --snapshot rendert
// der Prozess stattdessen Ansichten als PNG und beendet sich wieder.
let arguments = CommandLine.arguments

if arguments.contains("--benchmark") {
    Benchmark.run()
} else if arguments.contains("--snapshot") {
    SnapshotRunner.run(arguments: arguments)
} else {
    // Die App ist ausschliesslich fuer den Dunkelmodus entworfen. Das hier setzt
    // auch Menueleiste und Fensterrahmen dunkel, nicht nur den Inhalt.
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    PlanerApp.main()
}
