import Foundation
import AppKit
import WebKit

// What you have kept. Downloads work already; this is only the memory of them,
// so a file you fetched an hour ago is one click from the Finder rather than a
// hunt through a folder.

struct Keep: Codable, Identifiable, Equatable {
    var name: String
    var from: String
    var path: String
    var date: Date

    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }
    var stillThere: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A download still coming: its name once WebKit has one, and how far along.
@MainActor
final class Haul: ObservableObject, Identifiable {
    let id = UUID()
    let download: WKDownload
    @Published var name = "Download"
    @Published var fraction: Double = 0
    private var watch: NSKeyValueObservation?

    init(_ download: WKDownload) {
        self.download = download
        watch = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let through = progress.fractionCompleted
            Task { @MainActor in self?.fraction = through }
        }
    }

    func cancel() { download.cancel { _ in } }
}

@MainActor
final class Loot: ObservableObject {
    @Published private(set) var kept: [Keep] = []
    /// What is still arriving, newest first.
    @Published private(set) var hauls: [Haul] = []

    func start(_ download: WKDownload) {
        guard !hauls.contains(where: { $0.download === download }) else { return }
        hauls.insert(Haul(download), at: 0)
    }

    func name(_ download: WKDownload, _ name: String) {
        hauls.first { $0.download === download }?.name = name
    }

    func end(_ download: WKDownload) {
        hauls.removeAll { $0.download === download }
    }

    init() { load() }

    func add(_ keep: Keep) {
        kept.removeAll { $0.path == keep.path }
        kept.insert(keep, at: 0)
        // Fifty is more than anybody scrolls back through.
        if kept.count > 50 { kept.removeLast(kept.count - 50) }
        save()
    }

    func forget(_ keep: Keep) {
        kept.removeAll { $0.id == keep.id }
        save()
    }

    /// Only the list is emptied. Files you asked for are yours, and deleting
    /// them is the Finder's business, not a browser's.
    func forgetAll() {
        kept = []
        save()
    }

    func reveal(_ keep: Keep) {
        NSWorkspace.shared.activateFileViewerSelecting([keep.url])
    }

    func open(_ keep: Keep) {
        NSWorkspace.shared.open(keep.url)
    }

    private static var file: URL { Store.file("downloads.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Loot.file),
              let list = try? JSONDecoder().decode([Keep].self, from: data)
        else { return }
        kept = list
    }

    private func save() {
        let snapshot = kept
        let file = Loot.file
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: file, options: .atomic)
        }
    }
}
