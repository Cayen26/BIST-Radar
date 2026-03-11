// ContentView.swift – Root tab navigation
// BIST Radar AI

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if hasSeenOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .task {
            await appContainer.universeRepository.refreshIfNeeded(modelContext: modelContext)
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Piyasa", systemImage: "chart.bar.fill")
                }
                .tag(0)

            StocksListView()
                .tabItem {
                    Label("Hisseler", systemImage: "list.bullet.rectangle.fill")
                }
                .tag(1)

            WatchlistView()
                .tabItem {
                    Label("İzleme", systemImage: "star.fill")
                }
                .tag(2)

            NewsView()
                .tabItem {
                    Label("Haberler", systemImage: "newspaper.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(.brandAccent)
        .background(Color.surface1)
    }
}
