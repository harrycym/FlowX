import SwiftUI
import AppKit

struct UpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: PlanOption = .annual
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum PlanOption { case monthly, annual }

    private let darkText = Color(red: 0.08, green: 0.04, blue: 0.18)
    private let proGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.20, blue: 0.92), Color(red: 0.55, green: 0.15, blue: 0.98)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.96, blue: 1.0), Color.white],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    comparisonTable
                    planPicker
                    ctaSection
                }
            }

            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(7)
                    .background(Color.black.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: 480, height: 640)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(proGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.purple.opacity(0.35), radius: 12, x: 0, y: 6)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.top, 28)

            Text("Unlock NimbusGlide Pro")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(darkText)

            Text("Dictate longer. Speak in any language.\nUnlimited everything.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Side-by-side comparison

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Column headers — aligned with row content inside the card
            HStack(spacing: 0) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(width: 80)
                Text("Pro")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .padding(.vertical, 5)
                    .background(proGradient)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 40) // 20 outer + 20 inner card padding
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                comparisonRow(feature: "Words per month",     free: "2,000",       pro: "Unlimited")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Dictation length",    free: "5 min",       pro: "15 min")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Languages",           free: "1",           pro: "All 32")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Profiles",            free: "5",           pro: "Unlimited")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Dictionary & Snippets", free: "checkmark", pro: "checkmark")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Wake word commands",  free: "checkmark",   pro: "checkmark")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Priority processing", free: "xmark",       pro: "checkmark")
                Divider().padding(.leading, 20)
                comparisonRow(feature: "Auto language detect",free: "xmark",       pro: "checkmark")
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private func comparisonRow(feature: String, free: String, pro: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.callout)
                .foregroundColor(darkText)
                .frame(maxWidth: .infinity, alignment: .leading)

            comparisonCell(value: free, isPro: false)
                .frame(width: 80)

            comparisonCell(value: pro, isPro: true)
                .frame(width: 80)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func comparisonCell(value: String, isPro: Bool) -> some View {
        if value == "checkmark" {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundColor(isPro ? Color(red: 0.38, green: 0.20, blue: 0.92) : .green)
        } else if value == "xmark" {
            Image(systemName: "minus")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        } else {
            Text(value)
                .font(.callout.weight(isPro ? .semibold : .regular))
                .foregroundColor(isPro ? Color(red: 0.38, green: 0.20, blue: 0.92) : .secondary)
        }
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: 8) {
            planCard(
                option: .annual,
                title: "Annual",
                price: "$3",
                period: "/mo",
                detail: "$36 billed yearly",
                badge: "Save 40%"
            )
            planCard(
                option: .monthly,
                title: "Monthly",
                price: "$5",
                period: "/mo",
                detail: "Cancel anytime",
                badge: nil
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func planCard(option: PlanOption, title: String, price: String, period: String, detail: String, badge: String?) -> some View {
        let isSelected = selectedPlan == option
        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedPlan = option } }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color(red: 0.5, green: 0.2, blue: 0.94) : Color.secondary.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color(red: 0.5, green: 0.2, blue: 0.94))
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(darkText)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(proGradient)
                                .cornerRadius(5)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(price).font(.title2.weight(.bold)).foregroundColor(darkText)
                    Text(period).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(red: 0.38, green: 0.20, blue: 0.92).opacity(0.06) : Color.white)
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color(red: 0.5, green: 0.2, blue: 0.94).opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button(action: handleUpgrade) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isLoading ? "Opening checkout..." : "Start Pro — $1 for your first month")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(proGradient)
                .foregroundColor(.white)
                .cornerRadius(13)
                .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("7-day money-back guarantee")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Cancel anytime")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 20)
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
                    errorMessage = "Checkout coming soon! Payment is being set up."
                    isLoading = false
                }
            }
        }
    }
}
