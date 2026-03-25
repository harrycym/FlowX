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
                            .fill(
                                LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 72, height: 72)
                        Text(initials)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }

                    VStack(spacing: 4) {
                        Text(authManager.currentUser?.displayName ?? "User")
                            .font(.title3.weight(.semibold))
                        Text(authManager.currentUser?.email ?? "")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                    planBadge
                }
                .padding(.top, 8)

                // Plan card
                GroupBox {
                    VStack(spacing: 14) {
                        HStack {
                            Label("Plan", systemImage: "creditcard")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(usageTracker.isPro ? "Pro" : "Free")
                                .font(.callout.weight(.semibold))
                                .foregroundColor(usageTracker.isPro ? .purple : .secondary)
                        }

                        Divider()

                        HStack {
                            Label("Words used", systemImage: "text.word.spacing")
                                .font(.callout.weight(.medium))
                            Spacer()
                            if usageTracker.isPro {
                                Text("\(usageTracker.totalWordsUsed.formatted())")
                                    .font(.callout.weight(.medium))
                                + Text("  unlimited")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if let limit = usageTracker.wordLimit {
                                Text("\(usageTracker.totalWordsUsed.formatted()) / \(limit.formatted())")
                                    .font(.callout.weight(.medium))
                            }
                        }

                        if !usageTracker.isPro {
                            ProgressView(value: usageTracker.usageRatio)
                                .tint(usageTracker.usageRatio > 0.8 ? .orange : .purple)

                            Button(action: { showUpgrade = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                    Text("Upgrade to Pro — from $3/mo")
                                        .font(.callout.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                    .padding(4)
                }

                // Actions
                GroupBox {
                    VStack(spacing: 0) {
                        if usageTracker.isPro {
                            Button(action: {}) {
                                HStack {
                                    Image(systemName: "gear")
                                        .frame(width: 24)
                                    Text("Manage Subscription")
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .font(.caption2)
                Text("PRO")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(14)
        } else {
            Text("FREE")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(14)
        }
    }
}
