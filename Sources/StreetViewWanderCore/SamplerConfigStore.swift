import Foundation

public final class SamplerConfigStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let cacheURL: URL
    private let remoteURL: URL
    private let session: URLSession

    public init(
        fileManager: FileManager = .default,
        cacheURL: URL? = nil,
        remoteURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.cacheURL = cacheURL ?? Self.defaultCacheURL(fileManager: fileManager)
        self.remoteURL = remoteURL ?? Self.defaultRemoteURL
        self.session = session
    }

    public func loadAvailableConfig() -> SamplerConfig {
        if let repoConfig = Self.repoConfigURL(fileManager: fileManager),
           let config = try? load(from: repoConfig, source: "local repo sampler-config/latest.json") {
            return config
        }

        if let config = try? load(from: cacheURL, source: "cached sampler-config/latest.json") {
            return config
        }

        return .default
    }

    public func refreshRemoteConfig() async throws -> SamplerConfig {
        let (data, response) = try await session.data(from: remoteURL)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)

        var config = try JSONDecoder().decode(SamplerConfig.self, from: data)
        config.source = "remote \(remoteURL.absoluteString)"
        return config
    }

    public static let defaultRemoteURL = URL(
        string: "https://raw.githubusercontent.com/kmg0308/streetview-wander/main/sampler-config/latest.json"
    )!

    public static func defaultCacheURL(fileManager: FileManager = .default) -> URL {
        let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (base ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("StreetView Wander", isDirectory: true)
            .appendingPathComponent("sampler-config", isDirectory: true)
            .appendingPathComponent("latest.json", isDirectory: false)
    }

    private static func repoConfigURL(fileManager: FileManager) -> URL? {
        let repoCandidate = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/dev/streetview-wander", isDirectory: true)
        let config = repoCandidate
            .appendingPathComponent("sampler-config", isDirectory: true)
            .appendingPathComponent("latest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: config.path) else {
            return nil
        }
        return config
    }

    private func load(from url: URL, source: String) throws -> SamplerConfig {
        let data = try Data(contentsOf: url)
        var config = try JSONDecoder().decode(SamplerConfig.self, from: data)
        config.source = source
        return config
    }
}
