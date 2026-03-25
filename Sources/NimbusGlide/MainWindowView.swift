import SwiftUI

extension Notification.Name {
    static let nimbusglideNavigateToSettings = Notification.Name("nimbusglideNavigateToSettings")
    static let nimbusglideNavigateToHistory = Notification.Name("nimbusglideNavigateToHistory")
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"
    case settings = "Settings"
    case account = "Account"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "bolt.fill"
        case .style: return "paintbrush"
        case .settings: return "gear"
        case .account: return "person.crop.circle"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var pipelineState: PipelineState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var memoryManager: MemoryManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var authManager: AuthManager

    @State private var selectedItem: SidebarItem = .home
    @AppStorage("nimbusglide_onboarding_complete") private var hasCompletedOnboarding = false

    var body: some View {
        if !authManager.isAuthenticated {
            AuthView()
                .environmentObject(authManager)
        } else if !hasCompletedOnboarding {
            OnboardingView(isComplete: $hasCompletedOnboarding)
                .environmentObject(pipelineState)
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .background(NimbusColors.warmBg)
            }
            .frame(minWidth: 700, minHeight: 500)
            .onReceive(NotificationCenter.default.publisher(for: .nimbusglideNavigateToSettings)) { _ in
                selectedItem = .settings
            }
            .onReceive(NotificationCenter.default.publisher(for: .nimbusglideNavigateToHistory)) { _ in
                selectedItem = .home  // History is now on home
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(NimbusGradients.primary)
                Text("NimbusGlide")
                    .font(.headline.weight(.bold))
                    .foregroundColor(NimbusColors.heading)

                if usageTracker.isPro {
                    Text("Pro")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NimbusGradients.primary)
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)

            Divider()

            // Usage meter
            UsageMeter()
                .environmentObject(usageTracker)

            // Status pill
            StatusPill(status: pipelineState.status)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: NimbusLayout.sidebarWidth, max: 230)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedItem {
        case .home:
            HomeView()
                .environmentObject(pipelineState)
                .environmentObject(profileManager)
                .environmentObject(usageTracker)
                .environmentObject(settingsManager)
                .environmentObject(memoryManager)
                .environmentObject(authManager)
        case .dictionary:
            DictionaryView()
        case .snippets:
            SnippetsView()
        case .style:
            ProfilesView()
                .environmentObject(profileManager)
        case .settings:
            AppSettingsView()
                .environmentObject(settingsManager)
                .environmentObject(pipelineState)
                .environmentObject(usageTracker)
                .environmentObject(updateChecker)
        case .account:
            AccountView()
                .environmentObject(authManager)
                .environmentObject(usageTracker)
        }
    }
}
