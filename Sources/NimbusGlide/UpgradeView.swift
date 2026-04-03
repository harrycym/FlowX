import SwiftUI
import AppKit

struct UpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: PlanOption = .annual
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum PlanOption { case monthly, annual }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background
            LinearGradient(
                colors: [NimbusColors.warmBg, Color.white],
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
                    .foregroundColor(NimbusColors.muted)
                    .padding(7)
                    .background(Color.black.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: NimbusLayout.sheetWidth, height: 640)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(NimbusGradients.primary)
                    .frame(width: 56, height: 56)
                    .shadow(color: NimbusColors.violet.opacity(0.35), radius: 12, x: 0, y: 6)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.top, 28)

            Text("Unlock NimbusGlide Pro")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(NimbusColors.heading)

            Text("Dictate longer. Speak in any language.\nUnlimited everything.")
                .font(NimbusFonts.body)
                .foregroundColor(NimbusColors.muted)
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
                    .font(NimbusFonts.caption.weight(.bold))
                    .foregroundColor(NimbusColors.muted)
                    .frame(width: 80)
                Text("Pro")
                    .font(NimbusFonts.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .padding(.vertical, 5)
                    .background(NimbusGradients.primary)
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
            .cornerRadius(NimbusLayout.cardRadius)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private func comparisonRow(feature: String, free: String, pro: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(NimbusFonts.body)
                .foregroundColor(NimbusColors.heading)
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
                .font(NimbusFonts.caption.weight(.bold))
                .foregroundColor(isPro ? NimbusColors.indigo : NimbusColors.ready)
        } else if value == "xmark" {
            Image(systemName: "minus")
                .font(NimbusFonts.caption)
                .foregroundColor(NimbusColors.muted.opacity(0.5))
        } else {
            Text(value)
                .font(isPro ? NimbusFonts.bodyMedium : NimbusFonts.body)
                .foregroundColor(isPro ? NimbusColors.indigo : NimbusColors.muted)
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
                        .strokeBorder(isSelected ? NimbusColors.violet : Color.secondary.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(NimbusColors.violet)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(NimbusFonts.bodyMedium)
                            .foregroundColor(NimbusColors.heading)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NimbusGradients.primary)
                                .cornerRadius(5)
                        }
                    }
                    Text(detail)
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.muted)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(price).font(.title2.weight(.bold)).foregroundColor(NimbusColors.heading)
                    Text(period).font(NimbusFonts.caption).foregroundColor(NimbusColors.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                    .fill(isSelected ? NimbusColors.indigo.opacity(0.06) : Color.white)
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                    .strokeBorder(isSelected ? NimbusColors.violet.opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            if let error = errorMessage {
                Text(error)
                    .font(NimbusFonts.caption)
                    .foregroundColor(NimbusColors.error)
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
                    Text(isLoading ? "Opening checkout..." : selectedPlan == .monthly ? "Start Pro — $0.99 for your first month" : "Start Pro — $36/year (save 40%)")
                        .font(NimbusFonts.sectionHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(NimbusGradients.primary)
                .foregroundColor(.white)
                .cornerRadius(NimbusLayout.cardRadius)
                .shadow(color: NimbusColors.violet.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(NimbusFonts.small)
                        .foregroundColor(NimbusColors.ready)
                    Text("7-day money-back guarantee")
                        .font(NimbusFonts.small)
                        .foregroundColor(NimbusColors.muted)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(NimbusFonts.small)
                        .foregroundColor(NimbusColors.processing)
                    Text("Cancel anytime")
                        .font(NimbusFonts.small)
                        .foregroundColor(NimbusColors.muted)
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
