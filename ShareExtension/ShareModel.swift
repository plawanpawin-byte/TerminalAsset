import Foundation
import Observation
import TerminalAssetDomain

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var contents: [SharedContent] = []
    var intent: ShareIntent = .decide

    @ObservationIgnored private let providers: [NSItemProvider]
    @ObservationIgnored private let stagingDirectory: URL

    init(providers: [NSItemProvider]) {
        self.providers = providers
        self.stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-staging-\(UUID().uuidString)", isDirectory: true)
    }

    func load() async {
        let extractor = ItemExtractor(stagingDirectory: stagingDirectory)
        let result = await extractor.extract(from: providers)
        contents = result.contents
        phase = result.contents.isEmpty
            ? .failed("TerminalAsset can't add this kind of item yet.")
            : .ready
    }

    /// Queues everything in the App Group inbox. Returns true when the sheet can close.
    func save() async -> Bool {
        guard phase == .ready else { return false }
        phase = .saving

        let shareTime = Date()
        let jobs = contents.map { Self.job(for: $0, intent: intent, receivedAt: shareTime) }
        do {
            let inbox = try SharedInbox.appGroup()
            // File copies can be large, so they run off the main actor.
            try await Task.detached(priority: .userInitiated) {
                for job in jobs {
                    try inbox.enqueue(job.draft, payload: job.payload)
                }
            }.value
            try? FileManager.default.removeItem(at: stagingDirectory)
            return true
        } catch let error as SharedInboxError {
            phase = .failed(Self.message(for: error))
            return false
        } catch {
            phase = .failed("Couldn't save this. Please try again.")
            return false
        }
    }

    // MARK: - Private

    private struct EnqueueJob: Sendable {
        let draft: InboxDraft
        let payload: URL?
    }

    private static func job(for content: SharedContent, intent: ShareIntent, receivedAt: Date) -> EnqueueJob {
        switch content.payload {
        case .url(let url):
            return EnqueueJob(
                draft: InboxDraft(
                    kind: .url, title: content.title, urlString: url.absoluteString,
                    intent: intent, receivedAt: receivedAt
                ),
                payload: nil
            )
        case .text(let text):
            return EnqueueJob(
                draft: InboxDraft(kind: .text, title: content.title, text: text, intent: intent, receivedAt: receivedAt),
                payload: nil
            )
        case .file(let url, let isImage):
            return EnqueueJob(
                draft: InboxDraft(
                    kind: isImage ? .image : .file, title: content.title,
                    intent: intent, receivedAt: receivedAt
                ),
                payload: url
            )
        }
    }

    private static func message(for error: SharedInboxError) -> String {
        switch error {
        case .containerUnavailable:
            "TerminalAsset can't receive shared items on this device yet."
        case .payloadTooLarge(let limit):
            "That file is too large to share (limit \(limit / 1_048_576) MB)."
        case .payloadMissing, .readFailed, .writeFailed:
            "Couldn't save this. Please try again."
        }
    }
}
