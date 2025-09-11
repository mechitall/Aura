import Foundation

/// Supported speech recognition languages for Aura.
/// Extendable: add more cases with locale + flag + heuristics label.
enum SpeechLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en-US"
    case german  = "de-DE"
    case russian = "ru-RU"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german:  return "Deutsch"
        case .russian: return "Русский"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .german:  return "🇩🇪"
        case .russian: return "🇷🇺"
        }
    }
    
    var locale: Locale { Locale(identifier: rawValue) }
}
