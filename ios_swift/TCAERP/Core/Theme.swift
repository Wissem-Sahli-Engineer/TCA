import SwiftUI
import UIKit

/// Palette ported from src/styles/variables.css (light + dark themes).
extension Color {
    static let brand = Color(light: 0x252F6C, dark: 0x8AB4F8)
    static let brandWash = Color(light: 0xEDE9FE, dark: 0x28304A)
    static let ink = Color(light: 0x1A1A1A, dark: 0xE8EAED)
    static let muted = Color(light: 0x8A8A8F, dark: 0x9AA0A6)
    static let line = Color(light: 0xE7E7EA, dark: 0x3C4043)
    static let surface = Color(light: 0xF4F4F6, dark: 0x121212)
    static let card = Color(light: 0xFFFFFF, dark: 0x1E1E1F)
    static let cardInk = Color(light: 0x1A1A1A, dark: 0x000000)
    static let success = Color(light: 0x12A150, dark: 0x81C995)
    static let danger = Color(light: 0xE0455F, dark: 0xF28B82)
    static let warning = Color(light: 0xD97706, dark: 0xFDD663)

    // Chart / accent colours (same in both themes, as on the web).
    static let accentPurple = Color(hex: 0x8B5CF6)
    static let accentOrange = Color(hex: 0xF0924B)
    static let accentGreen = Color(hex: 0x22C55E)
    static let accentRed = Color(hex: 0xEF4444)
    static let accentGray = Color(hex: 0x9CA3AF)
    static let accentNavy = Color(hex: 0x1F3A5F)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Country: String, CaseIterable, Identifiable {
    case tunisia, libya

    var id: String { rawValue }
    var label: String { tr("countries.\(rawValue)") }
    var currency: String { self == .tunisia ? "TND" : "LYD" }
    var flag: String { self == .tunisia ? "🇹🇳" : "🇱🇾" }

    /// Label for a free-text country from client data.
    static func label(for text: String) -> String {
        detect(text)?.label ?? text
    }

    /// Spellings of the two countries in the free-text passport fields (same
    /// list as COUNTRY_ALIASES in backend/stats.py).
    private static let aliases: [Country: Set<String>] = [
        .tunisia: ["tunisia", "tunisie", "tunisian", "tunisien", "tunisienne", "tun", "tn", "تونس", "تونسي", "تونسية"],
        .libya: ["libya", "libye", "libyan", "libyen", "libyenne", "lby", "ly", "ليبيا", "ليبي", "ليبية"],
    ]

    static func detect(_ text: String?) -> Country? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { aliases[$0]?.contains(value) == true }
    }
}

// Pick-lists for client fields. Raw values must match backend/models.py;
// labels come from translations.json (shared with the website).

enum VisaStatus: String, CaseIterable, Identifiable {
    case new
    case documentReview = "document_review"
    case missingDocuments = "missing_documents"
    case readyForInvitation = "ready_for_invitation"
    case acceptedInSystem = "accepted_in_system"
    case invitationIssued = "invitation_issued"
    case clientNotified = "client_notified"
    case awaitingPassport = "awaiting_passport"
    case passportReceived = "passport_received"
    case fileSubmitted = "file_submitted"
    case awaitingResult = "awaiting_result"
    case passportReady = "passport_ready"
    case clientNotifiedPassportReady = "client_notified_passport_ready"
    case delivered
    case closed

    var id: String { rawValue }
    var label: String { tr("visa.\(rawValue)") }

    /// Still being worked on: past "new" and not delivered or closed.
    var isInProgress: Bool { ![.new, .delivered, .closed].contains(self) }

    var tone: StatusBadge.Tone {
        switch self {
        case .missingDocuments: return .danger
        case .documentReview, .awaitingPassport, .awaitingResult: return .warning
        case .passportReady, .clientNotifiedPassportReady, .delivered: return .success
        case .closed: return .neutral
        default: return .brand
        }
    }

    var color: Color {
        switch self {
        case .new: return .accentPurple
        case .documentReview: return .accentOrange
        case .missingDocuments: return .accentRed
        case .readyForInvitation: return Color(hex: 0x6366F1)
        case .acceptedInSystem: return Color(hex: 0x3B82F6)
        case .invitationIssued: return Color(hex: 0x0EA5E9)
        case .clientNotified: return Color(hex: 0x06B6D4)
        case .awaitingPassport: return Color(hex: 0xF59E0B)
        case .passportReceived: return Color(hex: 0x14B8A6)
        case .fileSubmitted: return Color(hex: 0x0D9488)
        case .awaitingResult: return Color(hex: 0xEAB308)
        case .passportReady: return .accentGreen
        case .clientNotifiedPassportReady: return Color(hex: 0x16A34A)
        case .delivered: return Color(hex: 0x15803D)
        case .closed: return .accentGray
        }
    }

    /// The visa counts as treated once the passport is ready (or later).
    var isTreated: Bool { [.passportReady, .clientNotifiedPassportReady, .delivered, .closed].contains(self) }
}

enum AlertReason: Hashable {
    case passportReady
    case tripSoon(date: String)

    /// A trip this many days away (or fewer) with an untreated visa is an alert.
    static let tripDays = 10

    var text: String {
        switch self {
        case .passportReady: return tr("alerts.passportReady")
        case .tripSoon(let date): return tr("alerts.tripSoon").replacingOccurrences(of: "{date}", with: date)
        }
    }
}

enum Currency: String, CaseIterable, Identifiable {
    case usd = "USD", eur = "EUR", tnd = "TND", lyd = "LYD"

    var id: String { rawValue }
    var label: String { tr("currencies.\(rawValue)") }
}

enum VisaType: String, CaseIterable, Identifiable {
    case preEntrySwift = "pre_entry_swift"
    case governmentInvitation = "government_invitation"
    case firstEntryConnect = "first_entry_connect"
    case companionS1S2 = "companion_s1_s2"
    case studyX1X2 = "study_x1_x2"
    case visaZ = "visa_z"
    case other

    var id: String { rawValue }
    var label: String { tr("visaType.\(rawValue)") }
}

enum PaymentMethod: String, CaseIterable, Identifiable {
    case cash, card, transfer, cheque

    var id: String { rawValue }
    var label: String { tr("paymentMethod.\(rawValue)") }
}

enum PaymentState: String, CaseIterable, Identifiable {
    case unpaid, partial, paid

    var id: String { rawValue }
    var label: String { tr("payment.\(rawValue)") }
    var tone: StatusBadge.Tone {
        switch self {
        case .unpaid: return .danger
        case .partial: return .warning
        case .paid: return .success
        }
    }
}

enum ClientCategory: String, CaseIterable, Identifiable {
    case normal, fair, reservation

    var id: String { rawValue }
    var label: String { tr("category.\(rawValue)") }
}

enum Fmt {
    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 3
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func num(_ value: Double) -> String {
        number.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func money(_ value: Double, _ currency: String) -> String {
        "\(currency) \(num(value))"
    }

    /// The API's date-only format ("2026-09-30").
    static let apiDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func today() -> String { apiDate.string(from: Date()) }

    static func currentPeriodLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: Date())
    }

    /// Parses user-typed numbers, accepting a comma as decimal separator.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
