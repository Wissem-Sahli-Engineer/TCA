import SwiftUI

/// App-wide toast messages, like src/components/ui/Toast.jsx.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    @Published var current: Toast?

    func show(_ text: String, error: Bool = false) {
        let toast = Toast(text: text, isError: error)
        withAnimation(.spring(duration: 0.35)) { current = toast }
        Task {
            try? await Task.sleep(for: .seconds(error ? 3.5 : 2.4))
            if current?.id == toast.id {
                withAnimation(.easeOut(duration: 0.25)) { current = nil }
            }
        }
    }
}

@MainActor
func toast(_ text: String, error: Bool = false) {
    ToastCenter.shared.show(text, error: error)
}

struct ToastOverlay: View {
    @ObservedObject var center = ToastCenter.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Color.danger : Color.success)
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.1).opacity(0.95), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { center.current = nil } }
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(center.current != nil)
    }
}
