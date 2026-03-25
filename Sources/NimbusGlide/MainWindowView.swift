import SwiftUI

extension Notification.Name {
    static let nimbusglideNavigateToSettings = Notification.Name("nimbusglideNavigateToSettings")
    static let nimbusglideNavigateToHistory = Notification.Name("nimbusglideNavigateToHistory")
    static let nimbusglideNavigateToAccount = Notification.Name("nimbusglideNavigateToAccount")
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Profile"
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

    /// Top items (features)
    static var topItems: [SidebarItem] { [.home, .dictionary, .snippets, .style] }
    /// Bottom items (meta)
    static var bottomItems: [SidebarItem] { [.settings, .account] }
}

struct MainWindowView: View {
    @EnvironmentObject var pipelineState: PipelineState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var memoryManager: MemoryManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var snippetsManager: SnippetsManager
    @EnvironmentObject var dictionaryManager: DictionaryManager

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
            .frame(minWidth: 800, minHeight: 540)
            .onReceive(NotificationCenter.default.publisher(for: .nimbusglideNavigateToSettings)) { _ in
                selectedItem = .settings
            }
            .onReceive(NotificationCenter.default.publisher(for: .nimbusglideNavigateToHistory)) { _ in
                selectedItem = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .nimbusglideNavigateToAccount)) { _ in
                selectedItem = .account
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

            List(selection: $selectedItem) {
                ForEach(SidebarItem.topItems) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)

            Spacer()

            // Bottom items — Settings & Account pinned above usage meter
            VStack(spacing: 2) {
                ForEach(SidebarItem.bottomItems) { item in
                    Button(action: { selectedItem = item }) {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.body)
                                .frame(width: 22)
                            Text(item.rawValue)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedItem == item ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .foregroundColor(selectedItem == item ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

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
                .environmentObject(dictionaryManager)
        case .snippets:
            SnippetsView()
                .environmentObject(snippetsManager)
        case .style:
            ProfilesView()
                .environmentObject(profileManager)
                .environmentObject(usageTracker)
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
