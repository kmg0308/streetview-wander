import AppKit
import Foundation
import SwiftUI

struct GitHubRepository: Equatable {
    let owner: String
    let name: String

    var apiBase: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)")!
    }
}

struct ReleaseInfo: Equatable {
    let version: String
    let displayName: String
    let zipURL: URL
    let htmlURL: URL?
    let targetCommitish: String
}

struct UpdateAvailability: Equatable {
    let currentVersion: String
    let release: ReleaseInfo

    var isAvailable: Bool {
        let installedCommit = UpdateService.installedBuildCommit()
        if installedCommit != "dev",
           !release.targetCommitish.isEmpty,
           !release.targetCommitish.hasPrefix(installedCommit) {
            return true
        }
        return UpdateService.compareVersions(release.version, currentVersion) == .orderedDescending
    }
}

enum UpdateServiceError: LocalizedError {
    case invalidRepository
    case invalidResponse
    case noDownloadURL
    case noDownloadedFile
    case notAnAppBundle

    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            "GitHub repository URL is invalid."
        case .invalidResponse:
            "GitHub returned an invalid response. Public releases are required unless the app is given a token."
        case .noDownloadURL:
            "No installable StreetViewWander ZIP was found in the latest release."
        case .noDownloadedFile:
            "Download a release ZIP first."
        case .notAnAppBundle:
            "Updates can only install into a packaged .app build."
        }
    }
}

enum UpdateService {
    static func parseRepository(_ text: String) -> GitHubRepository? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".git", with: "")
        if trimmed.isEmpty {
            return nil
        }

        if let url = URL(string: trimmed), let host = url.host, host.contains("github.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                return nil
            }
            return GitHubRepository(owner: parts[0], name: parts[1])
        }

        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            return nil
        }
        return GitHubRepository(owner: parts[0], name: parts[1])
    }

    static func checkLatestRelease(repository: GitHubRepository) async throws -> UpdateAvailability {
        let release = try await latestRelease(repository: repository)
        return UpdateAvailability(currentVersion: installedVersion(), release: release)
    }

    static func downloadRelease(_ release: ReleaseInfo) async throws -> URL {
        try await download(url: release.zipURL, suggestedName: "StreetViewWander-\(release.version).zip")
    }

    static func installDownloadedAppArchive(_ zipURL: URL) throws {
        let targetApp = Bundle.main.bundleURL
        guard targetApp.pathExtension == "app" else {
            throw UpdateServiceError.notAnAppBundle
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("streetview-wander-update-\(UUID().uuidString).zsh")

        let script = """
        #!/bin/zsh
        set -euo pipefail
        ZIP=\(shellQuote(zipURL.path))
        TARGET=\(shellQuote(targetApp.path))
        WORK="$(/usr/bin/mktemp -d)"
        /usr/bin/ditto -x -k "$ZIP" "$WORK"
        NEW_APP="$(/usr/bin/find "$WORK" -maxdepth 3 -type d -name 'StreetViewWander.app' | /usr/bin/head -n 1)"
        if [[ -z "$NEW_APP" ]]; then
            /bin/echo "StreetViewWander.app was not found in archive." >&2
            exit 2
        fi
        /bin/sleep 1
        /bin/rm -rf "$TARGET"
        /usr/bin/ditto "$NEW_APP" "$TARGET"
        /usr/bin/open "$TARGET"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    static func defaultRepositoryText() -> String {
        Bundle.main.object(forInfoDictionaryKey: "SWGitHubRepository") as? String ?? "kmg0308/streetview-wander"
    }

    static func installedBuildCommit() -> String {
        Bundle.main.object(forInfoDictionaryKey: "SWBuildCommit") as? String ?? "dev"
    }

    static func installedVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a > b { return .orderedDescending }
            if a < b { return .orderedAscending }
        }

        return .orderedSame
    }

    private static func latestRelease(repository: GitHubRepository) async throws -> ReleaseInfo {
        let url = repository.apiBase.appendingPathComponent("releases/latest")
        let object = try await jsonObject(from: url)
        guard let dict = object as? [String: Any],
              let assets = dict["assets"] as? [[String: Any]] else {
            throw UpdateServiceError.invalidResponse
        }

        guard let selected = releaseZipAsset(from: assets),
              let urlString = selected["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw UpdateServiceError.noDownloadURL
        }

        let tag = (dict["tag_name"] as? String) ?? (dict["name"] as? String) ?? "0.0.0"
        return ReleaseInfo(
            version: normalizedVersion(tag),
            displayName: (dict["name"] as? String) ?? tag,
            zipURL: downloadURL,
            htmlURL: (dict["html_url"] as? String).flatMap(URL.init(string:)),
            targetCommitish: (dict["target_commitish"] as? String) ?? ""
        )
    }

    private static func jsonObject(from url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("StreetViewWander", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateServiceError.invalidResponse
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private static func releaseZipAsset(from assets: [[String: Any]]) -> [String: Any]? {
        assets.first { assetName($0) == "streetviewwander.zip" }
            ?? assets.first {
                let name = assetName($0)
                return name.hasPrefix("streetviewwander-") && name.hasSuffix(".zip")
            }
            ?? assets.first {
                let name = assetName($0)
                return name.hasSuffix(".zip") && name.contains("streetview")
            }
            ?? assets.first { assetName($0).hasSuffix(".zip") }
    }

    private static func assetName(_ asset: [String: Any]) -> String {
        (asset["name"] as? String ?? "").lowercased()
    }

    private static func download(url: URL, suggestedName: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("StreetViewWander", forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateServiceError.invalidResponse
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let destination = downloads.appendingPathComponent(suggestedName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: tempURL, to: destination)
        return destination
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func normalizedVersion(_ string: String) -> String {
        var version = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.first == "v" || version.first == "V" {
            version.removeFirst()
        }
        return version
    }

    private static func versionParts(_ string: String) -> [Int] {
        normalizedVersion(string)
            .split { $0 == "." || $0 == "-" || $0 == "_" }
            .map { Int($0) ?? 0 }
    }
}

@MainActor
final class UpdateModel: ObservableObject {
    @Published var availability: UpdateAvailability?
    @Published var statusText = "Update checks use the latest GitHub Release."
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadedFile: URL?
    @Published var downloadedFileIsInstallable = false
    @Published var isSheetPresented = false
    private var autoCheckTask: Task<Void, Never>?

    var repositoryText: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "githubRepository") ?? ""
            if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return UpdateService.defaultRepositoryText()
        }
        set { UserDefaults.standard.set(newValue, forKey: "githubRepository") }
    }

    var updateLabel: String? {
        guard let availability, availability.isAvailable else {
            return nil
        }
        return "Update \(availability.release.version)"
    }

    func startAutoChecks() {
        guard autoCheckTask == nil else {
            return
        }

        autoCheckTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            checkIfConfigured(silent: true)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 21_600_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                checkIfConfigured(silent: true)
            }
        }
    }

    func checkIfConfigured(silent: Bool) {
        guard UpdateService.parseRepository(repositoryText) != nil else {
            return
        }
        checkLatestRelease(silent: silent)
    }

    func checkLatestRelease(silent: Bool) {
        guard !isChecking, !isDownloading else {
            return
        }
        guard let repository = UpdateService.parseRepository(repositoryText) else {
            statusText = UpdateServiceError.invalidRepository.localizedDescription
            availability = nil
            isSheetPresented = true
            return
        }

        isChecking = true
        if !silent {
            statusText = "Checking latest release..."
            isSheetPresented = true
        }

        Task {
            do {
                let result = try await UpdateService.checkLatestRelease(repository: repository)
                availability = result
                statusText = result.isAvailable
                    ? "Version \(result.release.version) is available."
                    : "StreetView Wander is up to date."
            } catch {
                statusText = error.localizedDescription
            }
            isChecking = false
        }
    }

    func updateNow(repositoryText newRepositoryText: String? = nil) {
        if let newRepositoryText {
            repositoryText = newRepositoryText
        }

        if downloadedFileIsInstallable {
            installDownloadedUpdate()
            return
        }

        if let release = availability?.release, availability?.isAvailable == true {
            downloadAndInstall(release: release)
            return
        }

        checkAndInstallLatestRelease()
    }

    func installDownloadedUpdate() {
        do {
            guard let downloadedFile else {
                throw UpdateServiceError.noDownloadedFile
            }
            try UpdateService.installDownloadedAppArchive(downloadedFile)
            NSApp.terminate(nil)
        } catch {
            statusText = error.localizedDescription
            isSheetPresented = true
        }
    }

    private func checkAndInstallLatestRelease() {
        guard !isChecking, !isDownloading else {
            return
        }
        guard let repository = UpdateService.parseRepository(repositoryText) else {
            statusText = UpdateServiceError.invalidRepository.localizedDescription
            availability = nil
            isSheetPresented = true
            return
        }

        isChecking = true
        statusText = "Checking latest release..."
        isSheetPresented = true

        Task {
            do {
                let result = try await UpdateService.checkLatestRelease(repository: repository)
                availability = result
                isChecking = false

                if result.isAvailable {
                    downloadAndInstall(release: result.release)
                } else {
                    statusText = "StreetView Wander is up to date."
                }
            } catch {
                statusText = error.localizedDescription
                isChecking = false
            }
        }
    }

    private func downloadAndInstall(release: ReleaseInfo) {
        guard !isDownloading else {
            return
        }

        isDownloading = true
        isSheetPresented = true
        statusText = "Downloading version \(release.version)..."

        Task {
            do {
                downloadedFile = try await UpdateService.downloadRelease(release)
                downloadedFileIsInstallable = true
                statusText = "Installing version \(release.version)..."
                isDownloading = false
                installDownloadedUpdate()
            } catch {
                statusText = error.localizedDescription
                isDownloading = false
            }
        }
    }
}

struct UpdateSheetView: View {
    @EnvironmentObject private var updates: UpdateModel
    @Environment(\.dismiss) private var dismiss
    @State private var repositoryText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Updates")
                        .font(.system(size: 18, weight: .semibold))
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    versionColumn("Installed", UpdateService.installedVersion())
                    Divider()
                    versionColumn("Latest", updates.availability?.release.version ?? "Not checked")
                }
                Text(updates.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Repository")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("owner/repository or GitHub URL", text: $repositoryText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveRepository()
                        updates.checkLatestRelease(silent: false)
                    }
            }

            HStack(spacing: 10) {
                if let downloadedFile = updates.downloadedFile {
                    Button("Show File") {
                        NSWorkspace.shared.activateFileViewerSelecting([downloadedFile])
                    }
                }
                Spacer()
                if updates.isChecking || updates.isDownloading {
                    ProgressView()
                        .scaleEffect(0.72)
                }
                Button(primaryButtonTitle) {
                    runPrimaryAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(primaryButtonDisabled)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            repositoryText = updates.repositoryText
            updates.checkIfConfigured(silent: true)
        }
    }

    private var statusTitle: String {
        if updates.downloadedFileIsInstallable {
            return "Ready to install"
        }
        if updates.availability?.isAvailable == true {
            return "Update available"
        }
        if updates.availability != nil {
            return "Up to date"
        }
        return "Not checked"
    }

    private var statusColor: Color {
        updates.availability?.isAvailable == true || updates.downloadedFileIsInstallable
            ? Color.primary
            : Color.secondary
    }

    private var primaryButtonTitle: String {
        if updates.downloadedFileIsInstallable {
            return "Install and Relaunch"
        }
        if updates.isChecking {
            return "Checking..."
        }
        if updates.isDownloading {
            return "Updating..."
        }
        if updates.availability?.isAvailable == true {
            return "Update Now"
        }
        return "Check for Updates"
    }

    private var primaryButtonDisabled: Bool {
        updates.isChecking || updates.isDownloading
            || repositoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func versionColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runPrimaryAction() {
        saveRepository()
        if updates.downloadedFileIsInstallable {
            updates.installDownloadedUpdate()
        } else if updates.availability?.isAvailable == true {
            updates.updateNow()
        } else {
            updates.checkLatestRelease(silent: false)
        }
    }

    private func saveRepository() {
        updates.repositoryText = repositoryText
    }
}
