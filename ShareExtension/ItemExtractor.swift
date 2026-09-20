import Foundation
import UniformTypeIdentifiers

/// One thing the user is sharing, already copied to a staging location when it is a file.
struct SharedContent: Sendable {
    enum Payload: Sendable {
        case url(URL)
        case text(String)
        case file(URL, isImage: Bool)
    }

    let title: String
    let payload: Payload
}

enum ExtractionError: Error, Sendable {
    case unreadable
}

/// Reads what the host app is sharing. Deliberately shallow: it copies bytes and reads names, and does no OCR,
/// embedding or analysis, because Share Extensions have tight memory and time limits.
///
/// Runs on the main actor because `NSItemProvider` is not `Sendable`; it only awaits system callbacks,
/// and the file copy itself happens inside the system's completion handler.
@MainActor
struct ItemExtractor {
    let stagingDirectory: URL

    /// Items that could not be read are counted, not thrown, so one bad attachment does not block the rest.
    func extract(from providers: [NSItemProvider]) async -> (contents: [SharedContent], failures: Int) {
        var contents: [SharedContent] = []
        var failures = 0
        for provider in providers {
            do {
                contents.append(try await load(provider))
            } catch {
                failures += 1
            }
        }
        return (contents, failures)
    }

    // MARK: - Per provider

    private func load(_ provider: NSItemProvider) async throws -> SharedContent {
        let isFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !isFileURL {
            let url = try await loadObject(URL.self, from: provider)
            let title = provider.suggestedName ?? url.host(percentEncoded: false) ?? url.absoluteString
            return SharedContent(title: title, payload: .url(url))
        }

        if let imageType = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) {
            let file = try await loadFile(from: provider, typeIdentifier: imageType.identifier)
            return SharedContent(title: file.lastPathComponent, payload: .file(file, isImage: true))
        }

        if isFileURL || provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            let typeIdentifier = isFileURL ? UTType.fileURL.identifier : UTType.data.identifier
            let file = try await loadFile(from: provider, typeIdentifier: typeIdentifier)
            return SharedContent(title: file.lastPathComponent, payload: .file(file, isImage: false))
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let text = try await loadObject(String.self, from: provider)
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            let title = firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
            return SharedContent(title: title.isEmpty ? String(localized: "Shared text") : title, payload: .text(text))
        }

        throw ExtractionError.unreadable
    }

    private func loadObject<T: _ObjectiveCBridgeable & Sendable>(
        _ type: T.Type,
        from provider: NSItemProvider
    ) async throws -> T where T._ObjectiveCType: NSItemProviderReading {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, error in
                if let value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: error ?? ExtractionError.unreadable)
                }
            }
        }
    }

    /// The system's temporary copy is only valid inside the completion handler, so it is copied out right there.
    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        let staging = stagingDirectory
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ExtractionError.unreadable)
                    return
                }
                do {
                    let directory = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let copy = directory.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
