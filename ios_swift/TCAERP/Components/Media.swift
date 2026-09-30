import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Image loaded from a protected API path (client photos need the bearer
/// token, so AsyncImage can't be used).
struct AuthImage: View {
    let path: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.surface
                if path?.isEmpty == false && !loaded {
                    ProgressView()
                } else {
                    Image(systemName: "person.fill").foregroundStyle(Color.muted.opacity(0.5))
                }
            }
        }
        .task(id: path) {
            guard let path, !path.isEmpty else { image = nil; loaded = true; return }
            image = await API.shared.image(path)
            loaded = true
        }
    }
}

/// Menu offering camera or photo library, then hands back a UIImage.
struct ImageSourceMenu<Label: View>: View {
    let onImage: (UIImage) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    SwiftUI.Label(tr("media.takePhoto"), systemImage: "camera")
                }
            }
            Button { showLibrary = true } label: {
                SwiftUI.Label(tr("media.photoLibrary"), systemImage: "photo.on.rectangle")
            }
        } label: {
            label()
        }
        .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onImage(image)
                }
                item = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in onImage(image) }
                .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

extension UploadFile {
    /// Reads a file picked with .fileImporter (security-scoped URL).
    static func from(url: URL) -> UploadFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return UploadFile(filename: url.lastPathComponent, mimeType: mime, data: data)
    }

    static func jpeg(_ image: UIImage, name: String) -> UploadFile? {
        image.jpegData(maxDimension: 2000).map { UploadFile(filename: name, mimeType: "image/jpeg", data: $0) }
    }
}

/// Downloads a protected file and previews it with Quick Look (share,
/// print and save-to-Files come for free).
@MainActor
final class FilePreviewer: ObservableObject {
    @Published var url: URL?
    @Published var loadingPath: String?

    func open(_ path: String, filename: String, failure: String) async {
        loadingPath = path
        defer { loadingPath = nil }
        do {
            url = try await API.shared.download(path, filename: filename)
        } catch {
            toast("\(failure) — \(error.localizedDescription)", error: true)
        }
    }
}

extension View {
    func filePreview(_ previewer: FilePreviewer) -> some View {
        modifier(FilePreviewModifier(previewer: previewer))
    }
}

private struct FilePreviewModifier: ViewModifier {
    @ObservedObject var previewer: FilePreviewer

    func body(content: Content) -> some View {
        content.quickLookPreview($previewer.url)
    }
}

/// Captures the app's key window, for the chatbot's "live helper".
@MainActor
func captureKeyWindow() -> UIImage? {
    let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
    guard let window else { return nil }
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    return renderer.image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
    }
}
