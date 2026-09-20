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
    /// Items the host app offered that could not be read. Shown, so a missing item is never a surprise.
    private(set) var skipped = 0
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
        skipped = result.failures
        phase = result.contents.isEmpty
            ? .failed(String(localized: "TerminalAsset can't add this kind of item yet."))
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
                // All or nothing: if a later item fails, the ones already queued are taken back out, so the sheet
                // never says "failed" while half of the share has quietly gone through.
                var queued: [UUID] = []
                do {
                    for job in jobs {
                        queued.append(try inbox.enqueue(job.draft, payload: job.payload).id)
                    }
                } catch {
                    for id in queued { inbox.remove(id: id) }
                    throw error
                }
            }.value
            try? FileManager.default.removeItem(at: stagingDirectory)
            return true
        } catch let error as SharedInboxError {
            phase = .failed(Self.message(for: error))
            return false
        } catch {
            phase = .failed(String(localized: "Couldn't save this. Please try again."))
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
            String(localized: "TerminalAsset can't receive shared items on this device yet.")
        case .payloadTooLarge(let limit):
            String(localized: "That file is too large to share (limit \(limit / 1_048_576) MB).")
        case .payloadMissing, .readFailed, .writeFailed:
            String(localized: "Couldn't save this. Please try again.")
        }
    }
}
