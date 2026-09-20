import SwiftUI
import UniformTypeIdentifiers

/// The exported data as a JSON file, for the system "Save to Files" sheet.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data
    let fileName: String

    init(data: Data = Data(), fileName: String = "TerminalAsset.json") {
        self.data = data
        self.fileName = fileName
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
        self.fileName = configuration.file.filename ?? "TerminalAsset.json"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
