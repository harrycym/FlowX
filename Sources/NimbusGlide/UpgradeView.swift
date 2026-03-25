import SwiftUI
import AppKit

struct UpgradeView: View {
    @EnvironmentObject var usageTracker: UsageTracker
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: PlanOption = .annual
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum PlanOption {
        case monthly, annual
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Upgrade to Pro")
                    .font(.title.weight(.bold))

                Text("Unlimited dictation. No word limits.\nSpeak freely, forever.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Plan cards
            VStack(spacing: 10) {
                // Annual (best value)
                planCard(
                    option: .annual,
                    title: "Annual",
                    price: "$3",
                    period: "/month",
                    detail: "$36 billed yearly",
                    badge: "Save 40%"
                )

                // Monthly
                planCard(
                    option: .monthly,
                    title: "Monthly",
                    price: "$5",
                    period: "/month",
                    detail: "Cancel anytime",
                    badge: nil
                )
            }
            .padding(.horizontal, 24)

            // Features
            VStack(alignment: .leading, spacing: 8) {
                featureRow("Unlimited dictation")
                featureRow("All AI models")
                featureRow("Custom profiles")
                featureRow("Priority processing")
            }
            .padding(.horizontal, 36)
            .padding(.top, 20)

            Spacer()

            // CTA
            VStack(spacing: 10) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: handleUpgrade) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(.circular)
                        }
                        Text(isLoading ? "Opening checkout..." : "Continue to Checkout")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)
                .padding(.horizontal, 24)

                Text("7-day money-back guarantee")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 380, height: 520)
    }

    private func planCard(option: PlanOption, title: String, price: String, period: String, detail: String, badge: String?) -> some View {
        Button(action: { selectedPlan = option }) {
            HStack(spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .strokeBorder(selectedPlan == option ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if selectedPlan == option {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(4)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(price)
                        .font(.title2.weight(.bold))
                    Text(period)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedPlan == option ? Color.accentColor.opacity(0.06) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selectedPlan == option ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private func handleUpgrade() {
        isLoading = true
        errorMessage = nil

        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            errorMessage = "Something went wrong"
            isLoading = false
            return
        }

        Task {
            do {
                let checkoutURL = try await appDelegate.apiClient.createCheckoutSession()
                await MainActor.run {
                    NSWorkspace.shared.open(checkoutURL)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    // Stripe not set up yet — show a friendly message
                    errorMessage = "Checkout coming soon! Payment is being set up."
                    isLoading = false
                }
            }
        }
    }
}
