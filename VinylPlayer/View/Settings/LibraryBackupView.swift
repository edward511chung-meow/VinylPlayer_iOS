import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryBackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var document = LibraryBackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var busy = false
    @State private var archive: LibraryBackup?
    @State private var error: String?
    @State private var success = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("backup.description"))
                    Button(L("backup.export")) { export() }.disabled(busy)
                    Button(L("backup.import")) { importing = true }.disabled(busy)
                }
                if busy { ProgressView(L("backup.working")) }
                if let archive {
                    Section(L("backup.review")) {
                        Text("\(archive.albums.count) \(L("search.albums")) · \(archive.playlists.count) \(L("library.playlists"))")
                        Text(L("backup.merge_hint")).font(.caption).foregroundStyle(.secondary)
                        Button(L("backup.merge")) { merge(archive) }.disabled(busy)
                        Button(L("common.cancel"), role: .cancel) { self.archive = nil }.disabled(busy)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if success { Label(L("backup.success"), systemImage: "checkmark.circle") }
            }
            .navigationTitle(L("backup.title"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "VinylPlayer-Backup") { result in
                if case .failure(let error) = result { self.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    private func export() {
        busy = true; error = nil; success = false
        Task { @MainActor in
            defer { busy = false }
            do {
                try context.save()
                let snapshot = try LibraryBackup.capture(context)
                let data = try await Task.detached { try JSONEncoder().encode(snapshot) }.value
                guard data.count <= 100 * 1024 * 1024 else { throw BackupError.tooLarge }
                document = LibraryBackupDocument(data: data); exporting = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func load(_ url: URL) {
        busy = true; error = nil; archive = nil; success = false
        Task { @MainActor in
            defer { busy = false }
            do {
                archive = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 100 * 1024 * 1024 else { throw BackupError.tooLarge }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 100 * 1024 * 1024 else { throw BackupError.tooLarge }
                    let decoded = try JSONDecoder().decode(LibraryBackup.self, from: data)
                    try decoded.validate()
                    return decoded
                }.value
            } catch { self.error = error.localizedDescription }
        }
    }
    private func merge(_ backup: LibraryBackup) {
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try context.save()
                try backup.merge(into: context.container)
                archive = nil; success = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
