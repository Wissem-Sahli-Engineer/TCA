import Charts
import PDFKit
import SwiftUI

/// Horizontal bars as a list: each label on its own line above its bar, so
/// long labels ("Client notified that passport is ready") never get
/// squeezed the way a Swift Charts axis does on a phone.
struct BarList: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        let value: Double
        let color: Color
        var valueText: String? = nil
    }

    let items: [Item]

    var body: some View {
        let maxValue = max(items.map(\.value).max() ?? 0, 1)
        VStack(spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.label)
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(item.valueText ?? Fmt.num(item.value))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(item.value > 0 ? Color.ink : Color.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.line.opacity(0.6))
                            Capsule()
                                .fill(item.color)
                                .frame(width: max(item.value > 0 ? 6 : 0, geo.size.width * item.value / maxValue))
                        }
                    }
                    .frame(height: 7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Inline PDF viewer (payslips), like the web's <iframe> preview.
struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
