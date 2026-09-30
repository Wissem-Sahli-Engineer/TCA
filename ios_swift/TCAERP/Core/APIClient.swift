import Foundation
import UIKit

struct APIError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? { message }
}

/// A file to send in a multipart/form-data upload.
struct UploadFile {
    let filename: String
    let mimeType: String
    let data: Data
}

/// Thin wrapper over URLSession for the FastAPI backend. Attaches the bearer
/// token to every request and signs the user out on a 401, like the web's
/// src/lib/apiAuth.js fetch wrapper.
@MainActor
final class API {
    static let shared = API()

    var token: String?
    var onUnauthorized: (() -> Void)?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 150 // passport extraction / chat run a local LLM
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let imageCache = NSCache<NSString, UIImage>()

    var baseURL: String {
        var base = AppSettings.shared.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    /// Builds a URL from an API path. Accepts both "/clients" and the
    /// public "/api/clients/..." form that the backend embeds in responses
    /// (photo, file and PDF URLs).
    func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        var path = path
        if path.hasPrefix("/api/") { path = String(path.dropFirst(4)) }
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError(status: 0, message: tr("settings.connectionFailed"))
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw APIError(status: 0, message: tr("settings.connectionFailed"))
        }
        return url
    }

    // MARK: JSON

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await perform(method: "GET", path: path, query: query, body: nil, contentType: nil)
        return try decode(data)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let data = try await perform(method: "POST", path: path, body: try encoder.encode(body), contentType: "application/json")
        return try decode(data)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let data = try await perform(method: "PUT", path: path, body: try encoder.encode(body), contentType: "application/json")
        return try decode(data)
    }

    /// POST whose response body the caller doesn't need.
    func postVoid(_ path: String, body: some Encodable) async throws {
        _ = try await perform(method: "POST", path: path, body: try encoder.encode(body), contentType: "application/json")
    }

    func postVoid(_ path: String) async throws {
        _ = try await perform(method: "POST", path: path, body: nil, contentType: nil)
    }

    func delete(_ path: String) async throws {
        _ = try await perform(method: "DELETE", path: path, body: nil, contentType: nil)
    }

    // MARK: Multipart

    func upload<T: Decodable>(_ path: String, field: String, files: [UploadFile]) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            let safeName = file.filename.replacingOccurrences(of: "\"", with: "'")
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(safeName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        let data = try await perform(
            method: "POST", path: path, body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try decode(data)
    }

    // MARK: Files

    /// Downloads a protected file (PDF, client document) to a temporary
    /// location so it can be shown in Quick Look or shared.
    func download(_ path: String, filename: String) async throws -> URL {
        let data = try await perform(method: "GET", path: path, body: nil, contentType: nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = filename.replacingOccurrences(of: "/", with: "_")
        let target = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
        try? FileManager.default.removeItem(at: target)
        try data.write(to: target)
        return target
    }

    func image(_ path: String) async -> UIImage? {
        let key = path as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard
            let data = try? await perform(method: "GET", path: path, body: nil, contentType: nil),
            let image = UIImage(data: data)
        else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    func invalidateImage(_ path: String) {
        imageCache.removeObject(forKey: path as NSString)
    }

    // MARK: Core

    private func perform(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data?,
        contentType: String?
    ) async throws -> Data {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError(status: 0, message: "\(tr("settings.connectionFailed")): \(baseURL) — \(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401, token != nil, !path.hasPrefix("/auth/login") {
                onUnauthorized?()
            }
            throw APIError(status: status, message: Self.detail(from: data) ?? "Request failed (\(status))")
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(status: 0, message: "Unexpected response from the server")
        }
    }

    /// FastAPI puts error text in {"detail": "..."} (or a list for 422s).
    private static func detail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = json["detail"] as? String { return text }
        if let list = json["detail"] as? [[String: Any]], let first = list.first?["msg"] as? String { return first }
        return nil
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

extension UIImage {
    /// Downscaled JPEG, keeping uploads and base64 payloads a sensible size.
    func jpegData(maxDimension: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    func dataURL(maxDimension: CGFloat = 1200) -> String? {
        jpegData(maxDimension: maxDimension).map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
    }

    convenience init?(dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        else { return nil }
        self.init(data: data)
    }
}
