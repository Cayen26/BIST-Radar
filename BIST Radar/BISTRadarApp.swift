// BISTRadarApp.swift – App entry point (SwiftUI lifecycle)
// BIST Radar AI

import SwiftUI
import SwiftData

@main
struct BISTRadarApp: App {

    @StateObject private var appContainer = AppContainer.shared
    @AppStorage("preferredColorScheme") private var colorSchemePref = "dark"

    private var preferredScheme: ColorScheme? {
        switch colorSchemePref {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil   // "system" → iOS kararı
        }
    }

    // SwiftData ModelContainer
    private static let modelContainer: ModelContainer = {
        let schema = Schema([Company.self, WatchlistItem.self, AlertRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData ModelContainer başlatılamadı: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appContainer)
                .preferredColorScheme(preferredScheme)
        }
        .modelContainer(Self.modelContainer)
    }
}
