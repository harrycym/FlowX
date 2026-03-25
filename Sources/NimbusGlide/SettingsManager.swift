import Foundation
import SwiftUI

enum GroqModel: String, CaseIterable, Identifiable {
    case llama33_70b = "llama-3.3-70b-versatile"
    case llama4_scout = "meta-llama/llama-4-scout-17b-16e-instruct"
    case kimi_k2 = "moonshotai/kimi-k2-instruct-0905"
    case qwen3_32b = "qwen/qwen3-32b"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llama33_70b:  return "Llama 3.3 70B"
        case .llama4_scout: return "Llama 4 Scout"
        case .kimi_k2:      return "Kimi K2"
        case .qwen3_32b:    return "Qwen 3 32B"
        }
    }
}

class SettingsManager: ObservableObject {
    private static let llmModelKey       = "nimbusglide_llm_model"
    private static let hotkeyKey         = "nimbusglide_hotkey"
    private static let customKeyCodeKey  = "nimbusglide_custom_key_code"
    private static let customKeyLabelKey = "nimbusglide_custom_key_label"
    private static let autoCopyKey       = "nimbusglide_auto_copy"
    private static let statusIndicatorKey = "nimbusglide_status_indicator"
    private static let languagesKey       = "nimbusglide_languages"

    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: Self.llmModelKey) }
    }

    @Published var hotkey: HotkeyChoice {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: Self.hotkeyKey) }
    }

    /// Raw key code for the custom hotkey (only used when hotkey == .custom)
    @Published var customKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(customKeyCode), forKey: Self.customKeyCodeKey) }
    }

    /// Human-readable label for the custom key (e.g. "F5", "A")
    @Published var customKeyLabel: String {
        didSet { UserDefaults.standard.set(customKeyLabel, forKey: Self.customKeyLabelKey) }
    }

    /// Auto-copy processed text to clipboard
    @Published var autoCopyToClipboard: Bool {
        didSet { UserDefaults.standard.set(autoCopyToClipboard, forKey: Self.autoCopyKey) }
    }

    /// Show floating status indicator overlay
    @Published var showStatusIndicator: Bool {
        didSet { UserDefaults.standard.set(showStatusIndicator, forKey: Self.statusIndicatorKey) }
    }

    /// Languages the LLM is allowed to respond in
    @Published var selectedLanguages: [String] {
        didSet { UserDefaults.standard.set(selectedLanguages, forKey: Self.languagesKey) }
    }

    static let supportedLanguages: [String] = [
        "English", "Spanish", "French", "German", "Italian", "Portuguese",
        "Dutch", "Russian", "Chinese (Simplified)", "Chinese (Traditional)",
        "Japanese", "Korean", "Arabic", "Hindi", "Turkish", "Vietnamese",
        "Thai", "Indonesian", "Polish", "Ukrainian", "Czech", "Romanian",
        "Swedish", "Danish", "Norwegian", "Finnish", "Greek", "Hebrew",
        "Hungarian", "Bengali", "Tamil", "Malay"
    ]

    init() {
        let savedModel = UserDefaults.standard.string(forKey: Self.llmModelKey) ?? ""
        if savedModel == "llama-3.1-8b-instant" || savedModel.isEmpty {
            self.llmModel = GroqModel.llama33_70b.rawValue
        } else {
            self.llmModel = savedModel
        }

        if let saved = UserDefaults.standard.string(forKey: Self.hotkeyKey),
           let choice = HotkeyChoice(rawValue: saved) {
            self.hotkey = choice
        } else {
            self.hotkey = .fn
        }

        self.customKeyCode  = UInt16(UserDefaults.standard.integer(forKey: Self.customKeyCodeKey))
        self.customKeyLabel = UserDefaults.standard.string(forKey: Self.customKeyLabelKey) ?? "—"
        self.autoCopyToClipboard = UserDefaults.standard.object(forKey: Self.autoCopyKey) as? Bool ?? true
        self.showStatusIndicator = UserDefaults.standard.object(forKey: Self.statusIndicatorKey) as? Bool ?? true
        self.selectedLanguages = UserDefaults.standard.stringArray(forKey: Self.languagesKey) ?? ["English"]
    }

}
