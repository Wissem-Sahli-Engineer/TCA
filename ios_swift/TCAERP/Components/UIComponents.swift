import SwiftUI

// MARK: Cards & tiles

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.line.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var note: String? = nil
    var accent: Color = .brand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(accent).frame(width: 28, height: 4)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Color.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let note {
                Text(note).font(.caption).foregroundStyle(Color.muted).lineLimit(1)
            }
        }
        .card(padding: 14)
    }
}

struct PageHeader: View {
    let kicker: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.muted)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Badges

struct StatusBadge: View {
    let text: String
    let tone: Tone

    enum Tone { case success, warning, danger, brand, neutral }

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    /// Request / account statuses (approved, pending, active…), translated.
    init(status: String) {
        let key = "status.\(status)"
        let label = tr(key)
        self.text = label == key ? status.capitalized : label
        switch status {
        case "approved", "active": tone = .success
        case "pending": tone = .warning
        case "rejected": tone = .danger
        default: tone = .brand
        }
    }

    init(visa: VisaStatus) {
        text = visa.label
        tone = visa.tone
    }

    init(payment: PaymentState) {
        text = payment.label
        tone = payment.tone
    }

    private var color: Color {
        switch tone {
        case .success: return .success
        case .warning: return .warning
        case .danger: return .danger
        case .brand: return .brand
        case .neutral: return .muted
        }
    }

    var body: some View {
        // Long statuses ("Client notified that passport is ready") wrap onto a
        // second line instead of squeezing whatever sits next to the badge.
        Text(text)
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Empty & loading states

struct EmptyRow: View {
    let text: String
    var systemImage: String = "tray"

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(Color.muted.opacity(0.6))
                Text(text).font(.subheadline).foregroundStyle(Color.muted).multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var loading = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(role == .destructive ? Color.danger : Color.brand)
        .disabled(loading)
    }
}

// MARK: Labeled form rows

/// ✓ when the passport's own check digit confirms a value, ⚠ when it needs a look
/// (shown after reading a passport); nothing for the rest.
struct ReadMark: View {
    let status: String?

    var body: some View {
        switch status {
        case "verified":
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.success)
                .accessibilityLabel(tr("clients.markVerified"))
        case "review":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)
                .accessibilityLabel(tr("clients.markReview"))
        default:
            EmptyView()
        }
    }
}

/// A text field with a small caption above, matching the web's Field label.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences
    var status: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label.capitalizedFirst)
                ReadMark(status: status)
            }
            .font(.caption)
            .foregroundStyle(Color.muted)
            TextField(placeholder.isEmpty ? label.capitalizedFirst : placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalize)
                .autocorrectionDisabled(keyboard != .default)
        }
        .padding(.vertical, 2)
    }
}

/// Date picker bound to an API date string ("YYYY-MM-DD").
struct DateField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        DatePicker(label.capitalizedFirst, selection: Binding(
            get: { Fmt.apiDate.date(from: text) ?? Date() },
            set: { text = Fmt.apiDate.string(from: $0) }
        ), displayedComponents: .date)
    }
}

/// Date that may be left empty (passport dates the AI couldn't read).
struct OptionalDateField: View {
    let label: String
    @Binding var text: String
    var status: String? = nil

    var body: some View {
        HStack {
            if text.isEmpty {
                HStack(spacing: 4) {
                    Text(label.capitalizedFirst)
                    ReadMark(status: status)
                }
                Spacer()
                Button(tr("common.add")) { text = Fmt.today() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                DateField(label: label, text: $text)
                ReadMark(status: status)
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension String {
    /// "passport number" → "Passport number" (web labels are lowercase).
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Runs an async action, showing its error as a toast.
@MainActor
func attempt(_ failure: String? = nil, _ work: () async throws -> Void) async {
    do {
        try await work()
    } catch {
        toast(failure.map { "\($0) — \(error.localizedDescription)" } ?? error.localizedDescription, error: true)
    }
}
