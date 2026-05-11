import Foundation

public final class HistoryStore {
    public static let limit = 1_000

    private let fileManager: FileManager
    private let historyURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.historyURL = Self.defaultHistoryURL(fileManager: fileManager)
    }

    public func load() throws -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        let data = try Data(contentsOf: historyURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryEntry].self, from: data)
    }

    @discardableResult
    public func append(_ panorama: Panorama) throws -> [HistoryEntry] {
        var entries = try load()
        entries.insert(HistoryEntry(panorama: panorama), at: 0)
        if entries.count > Self.limit {
            entries = Array(entries.prefix(Self.limit))
        }
        try save(entries)
        return entries
    }

    public func save(_ entries: [HistoryEntry]) throws {
        try fileManager.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: historyURL, options: .atomic)
    }

    public static func defaultHistoryURL(fileManager: FileManager = .default) -> URL {
        let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (base ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("StreetView Wander", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}

