import SwiftUI
import AppKit

struct AccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var usageTracker: UsageTracker
    @State private var showUpgrade = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile card
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(NimbusGradients.subtle)
                            .frame(width: 72, height: 72)
                        Text(initials)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(NimbusGradients.primary)
                    }

                    VStack(spacing: 6) {
                        Text(authManager.currentUser?.displayName ?? "User")
                            .font(NimbusFonts.pageTitle)
                        Text(authManager.currentUser?.email ?? "")
                            .font(NimbusFonts.body)
                            .foregroundColor(NimbusColors.muted)
                    }

                    planBadge
                }
                .padding(.top, 8)

                // Plan card
                VStack(spacing: 16) {
                    HStack {
                        Label("Plan", systemImage: "creditcard")
                            .font(NimbusFonts.bodyMedium)
                        Spacer()
                        Text(usageTracker.isPro ? "Pro" : "Free")
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(usageTracker.isPro ? NimbusColors.violet : NimbusColors.muted)
                    }

                    Divider()

                    HStack {
                        Label("Words used", systemImage: "text.word.spacing")
                            .font(NimbusFonts.bodyMedium)
                        Spacer()
                        if usageTracker.isPro {
                            Text("\(usageTracker.totalWordsUsed.formatted())")
                                .font(NimbusFonts.bodyMedium)
                            + Text("  unlimited")
                                .font(NimbusFonts.caption)
                                .foregroundColor(NimbusColors.muted)
                        } else if let limit = usageTracker.wordLimit {
                            Text("\(usageTracker.totalWordsUsed.formatted()) / \(limit.formatted())")
                                .font(NimbusFonts.bodyMedium)
                        }
                    }

                    if !usageTracker.isPro {
                        ProgressView(value: usageTracker.usageRatio)
                            .tint(usageTracker.usageRatio > 0.8 ? NimbusColors.processing : NimbusColors.violet)

                        Button(action: { showUpgrade = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text("Upgrade to Pro — from $3/mo")
                                    .font(NimbusFonts.bodyMedium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(16)
                .nimbusCard()

                // Plan limits
                VStack(alignment: .leading, spacing: 12) {
                    Label("Plan Limits", systemImage: "list.bullet")
                        .font(NimbusFonts.bodyMedium)

                    HStack {
                        Text("Words per Month")
                            .font(NimbusFonts.body)
                        Spacer()
                        Text(usageTracker.isPro ? "Unlimited" : "\(usageTracker.wordLimit?.formatted() ?? "2,000")")
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(usageTracker.isPro ? NimbusColors.violet : NimbusColors.muted)
                    }
                    Divider()
                    HStack {
                        Text("Max Dictation Length")
                            .font(NimbusFonts.body)
                        Spacer()
                        Text(usageTracker.isPro ? "15 minutes" : "5 minutes")
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(usageTracker.isPro ? NimbusColors.violet : NimbusColors.muted)
                    }
                    Divider()
                    HStack {
                        Text("Profiles")
                            .font(NimbusFonts.body)
                        Spacer()
                        Text(usageTracker.isPro ? "Unlimited" : "5 max")
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(usageTracker.isPro ? NimbusColors.violet : NimbusColors.muted)
                    }
                    Divider()
                    HStack {
                        Text("Languages")
                            .font(NimbusFonts.body)
                        Spacer()
                        Text(usageTracker.isPro ? "Unlimited (auto-detect)" : "1 language")
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(usageTracker.isPro ? NimbusColors.violet : NimbusColors.muted)
                    }
                }
                .padding(16)
                .nimbusCard()

                // Actions
                VStack(spacing: 0) {
                    if usageTracker.isPro {
                        Button(action: {
                            // Opens Stripe billing portal in browser
                            NSWorkspace.shared.open(URL(string: "https://nimbusglide.ai/account")!)
                        }) {
                            HStack {
                                Image(systemName: "globe")
                                    .frame(width: 24)
                                Text("Manage Subscription")
                                    .font(NimbusFonts.body)
                                Spacer()
                                Text("Opens browser")
                                    .font(NimbusFonts.caption)
                                    .foregroundColor(NimbusColors.muted)
                                Image(systemName: "arrow.up.forward")
                                    .font(NimbusFonts.caption)
                                    .foregroundColor(NimbusColors.muted)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 4)
                    }

                    Button(role: .destructive, action: { authManager.signOut() }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(width: 24)
                            Text("Sign Out")
                            Spacer()
                        }
                        .foregroundColor(NimbusColors.error)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .nimbusCard()
            }
            .padding(NimbusLayout.contentPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
        }
    }

    private var initials: String {
        let name = authManager.currentUser?.displayName ?? authManager.currentUser?.email ?? "?"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    @ViewBuilder
    private var planBadge: some View {
        if usageTracker.isPro {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(NimbusFonts.small)
                Text("PRO")
                    .font(NimbusFonts.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(NimbusGradients.primary)
            .cornerRadius(14)
        } else {
            Text("FREE")
                .font(NimbusFonts.caption.weight(.bold))
                .foregroundColor(NimbusColors.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(14)
        }
    }
}
