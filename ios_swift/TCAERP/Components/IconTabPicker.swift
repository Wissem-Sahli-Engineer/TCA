import SwiftUI

/// Icon-and-label tab bar for switching sections inside a screen — the
/// native counterpart of the web's floating menu (src/components/ui/nav.jsx).
struct IconTabPicker<Value: Hashable>: View {
    struct Item {
        let value: Value
        let label: String
        let systemImage: String
        var badge: Int? = nil
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let isSelected = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.value }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                            .frame(height: 20)
                            .overlay(alignment: .topTrailing) {
                                if let badge = item.badge, badge > 0 {
                                    Text("\(badge)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color.danger, in: Capsule())
                                        .offset(x: 12, y: -6)
                                }
                            }
                        Text(item.label)
                            .font(.caption2.weight(isSelected ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.brand : Color.muted)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.brandWash)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().stroke(Color.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}
