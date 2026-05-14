import Foundation

public final class FeedbackStore {
    public static let limit = 2_000

    private let fileManager: FileManager
    private let feedbackURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.feedbackURL = Self.defaultFeedbackURL(fileManager: fileManager)
    }

    public func load() throws -> [PlaceFeedbackEntry] {
        guard fileManager.fileExists(atPath: feedbackURL.path) else {
            return []
        }

        let data = try Data(contentsOf: feedbackURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PlaceFeedbackEntry].self, from: data)
    }

    @discardableResult
    public func append(_ entry: PlaceFeedbackEntry) throws -> [PlaceFeedbackEntry] {
        var entries = try load()
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries = Array(entries.prefix(Self.limit))
        }
        try save(entries)
        return entries
    }

    public func save(_ entries: [PlaceFeedbackEntry]) throws {
        try fileManager.createDirectory(
            at: feedbackURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: feedbackURL, options: .atomic)
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: feedbackURL.path) {
            try fileManager.removeItem(at: feedbackURL)
        }
    }

    public static func defaultFeedbackURL(fileManager: FileManager = .default) -> URL {
        let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (base ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("StreetView Wander", isDirectory: true)
            .appendingPathComponent("feedback.json", isDirectory: false)
    }
}
