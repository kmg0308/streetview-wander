import Foundation

public enum SearchTelemetryEventKind: String, Codable, Equatable, Hashable, Sendable {
    case candidateAttempted
    case metadataResult
    case visitRecorded
    case feedbackGiven
    case configLoaded
    case configLoadFailed
}

public struct SearchTelemetryEvent: Codable, Equatable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var deviceId: String?
    public var kind: SearchTelemetryEventKind
    public var requestedLocation: PanoramaLocation?
    public var location: PanoramaLocation?
    public var sceneKind: SearchSceneKind?
    public var densityTier: SearchDensityTier?
    public var areaLabel: String?
    public var countryLabel: String?
    public var continentLabel: String?
    public var status: String?
    public var attempts: Int?
    public var feedbackKind: PlaceFeedbackKind?
    public var reasonSummary: String?
    public var reasonDetails: [String]?
    public var configSource: String?

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        deviceId: String? = nil,
        kind: SearchTelemetryEventKind,
        requestedLocation: PanoramaLocation? = nil,
        location: PanoramaLocation? = nil,
        sceneKind: SearchSceneKind? = nil,
        densityTier: SearchDensityTier? = nil,
        areaLabel: String? = nil,
        countryLabel: String? = nil,
        continentLabel: String? = nil,
        status: String? = nil,
        attempts: Int? = nil,
        feedbackKind: PlaceFeedbackKind? = nil,
        reasonSummary: String? = nil,
        reasonDetails: [String]? = nil,
        configSource: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.deviceId = deviceId
        self.kind = kind
        self.requestedLocation = requestedLocation
        self.location = location
        self.sceneKind = sceneKind
        self.densityTier = densityTier
        self.areaLabel = areaLabel
        self.countryLabel = countryLabel
        self.continentLabel = continentLabel
        self.status = status
        self.attempts = attempts
        self.feedbackKind = feedbackKind
        self.reasonSummary = reasonSummary
        self.reasonDetails = reasonDetails
        self.configSource = configSource
    }
}

public final class TelemetryStore {
    private let fileManager: FileManager
    private let eventsDirectory: URL
    private let deviceId: String

    public init(
        fileManager: FileManager = .default,
        eventsDirectory: URL? = nil,
        deviceId: String? = nil
    ) {
        self.fileManager = fileManager
        self.eventsDirectory = eventsDirectory ?? Self.defaultEventsDirectory(fileManager: fileManager)
        self.deviceId = deviceId ?? Self.defaultDeviceId()
    }

    public func append(_ event: SearchTelemetryEvent) throws {
        var event = event
        event.deviceId = event.deviceId ?? deviceId

        let directory = eventsDirectory.appendingPathComponent(deviceId, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("\(Self.dayString(for: event.createdAt)).ndjson")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultEventsDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["STREETVIEW_WANDER_TELEMETRY_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let repoCandidate = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/dev/streetview-wander", isDirectory: true)
        if fileManager.fileExists(atPath: repoCandidate.appendingPathComponent(".git").path) {
            return repoCandidate
                .appendingPathComponent("telemetry", isDirectory: true)
                .appendingPathComponent("events", isDirectory: true)
        }

        let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (base ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("StreetView Wander", isDirectory: true)
            .appendingPathComponent("telemetry", isDirectory: true)
            .appendingPathComponent("events", isDirectory: true)
    }

    private static func defaultDeviceId() -> String {
        let raw = ProcessInfo.processInfo.hostName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return value.isEmpty ? "unknown-mac" : value
    }

    private static func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
