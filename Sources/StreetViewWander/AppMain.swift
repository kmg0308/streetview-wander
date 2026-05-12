import AppKit
import StreetViewWanderCore
import SwiftUI

@main
struct StreetViewWanderApp: App {
    @StateObject private var model = WanderModel()
    @StateObject private var updates = UpdateModel()

    var body: some Scene {
        WindowGroup("StreetView Wander") {
            ContentView()
                .environmentObject(model)
                .environmentObject(updates)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    updates.startAutoChecks()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("StreetView Wander") {
                Button("Settings...") {
                    model.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("Check for Updates...") {
                    updates.checkLatestRelease(silent: false)
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: WanderModel
    @EnvironmentObject private var updates: UpdateModel

    var body: some View {
        ZStack {
            StreetViewWebView(
                panorama: model.panorama,
                browserAPIKey: model.browserAPIKey
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomStatus
            }
            .padding(16)

            if model.activePanel != .none {
                sidePanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.08))
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $updates.isSheetPresented) {
            UpdateSheetView()
                .environmentObject(updates)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            toolbarGroup {
                Button {
                    withAnimation(.snappy) {
                        model.activePanel = model.activePanel == .history ? .none : .history
                    }
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(OverlayButtonStyle(isActive: model.activePanel == .history))

                Button {
                    withAnimation(.snappy) {
                        model.activePanel = model.activePanel == .details ? .none : .details
                    }
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(OverlayButtonStyle(isActive: model.activePanel == .details))
            }

            toolbarGroup {
                Button {
                    withAnimation(.snappy) {
                        model.activePanel = model.activePanel == .scope ? .none : .scope
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Scope")
                            .foregroundStyle(.secondary)
                        Text(model.selectedScopeLabel)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(OverlayButtonStyle(isActive: model.activePanel == .scope))
                .frame(width: 190)
            }

            toolbarGroup {
                Button {
                    model.isSettingsPresented = true
                } label: {
                    Image(systemName: "key")
                }
                .buttonStyle(IconOverlayButtonStyle())
                .help("API key settings")
                .accessibilityLabel("API key settings")

                if let label = updates.updateLabel {
                    Button {
                        updates.updateNow()
                    } label: {
                        Label(label, systemImage: "arrow.down.circle")
                            .lineLimit(1)
                    }
                    .buttonStyle(OverlayButtonStyle(isActive: true))
                    .frame(maxWidth: 150)
                } else {
                    Button {
                        updates.isSheetPresented = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(IconOverlayButtonStyle())
                    .help("Updates")
                    .accessibilityLabel("Updates")
                }
            }

            Button {
                model.randomPlace()
            } label: {
                Label(model.isLoading ? "Finding..." : "Random place", systemImage: "shuffle")
            }
            .disabled(model.isLoading)
            .buttonStyle(PrimaryOverlayButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func toolbarGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(4)
        .background(Color(red: 0.07, green: 0.08, blue: 0.08).opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12))
        )
    }

    private var bottomStatus: some View {
        HStack(spacing: 12) {
            if !model.hasBrowserAPIKey || !model.hasMetadataAPIKey {
                Button("Add API Keys") {
                    model.isSettingsPresented = true
                }
                .buttonStyle(PrimaryOverlayButtonStyle())
            }

            Text(model.errorText ?? model.statusText)
                .lineLimit(2)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.errorText == nil ? Color.white.opacity(0.86) : Color(red: 1, green: 0.82, blue: 0.76))
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(metadataUsageStatus)
                .lineLimit(1)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataUsageStatus: String {
        if let remaining = model.metadataRequestsRemaining {
            return "Metadata API \(formatCount(model.metadataRequestsUsed))/\(formatCount(model.metadataRequestLimit)) · \(formatCount(remaining)) left"
        }
        return "Metadata API used \(formatCount(model.metadataRequestsUsed)) · no limit"
    }

    private var sidePanel: some View {
        HStack {
            Spacer()
            Group {
                switch model.activePanel {
                case .none:
                    EmptyView()
                case .details:
                    DetailsPanel()
                case .history:
                    HistoryPanel()
                case .scope:
                    ScopePanel()
                }
            }
            .environmentObject(model)
            .frame(width: 360)
            .padding(16)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.14))
            )
            .padding(.top, 70)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }
}

struct ScopePanel: View {
    @EnvironmentObject private var model: WanderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("Random Scope")

            Picker("Continent", selection: $model.selectedContinentId) {
                Text("Worldwide").tag("")
                ForEach(model.locationOptions.continents) { continent in
                    Text("\(continent.label) (\(continent.countryCount))").tag(continent.id)
                }
            }

            Picker("Country", selection: $model.selectedCountryId) {
                Text("All countries").tag("")
                ForEach(model.filteredCountries) { country in
                    Text(country.label).tag(country.id)
                }
            }

            Button("Clear Scope") {
                model.clearScope()
            }

            Text(model.selectedScopeLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .panelText()
    }
}

struct DetailsPanel: View {
    @EnvironmentObject private var model: WanderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("Current Start Point")

            if let panorama = model.panorama {
                detail("Scope", panorama.scopeLabel)
                detail("Area", panorama.areaLabel)
                if let country = panorama.countryLabel {
                    detail("Country", country)
                }
                if let continent = panorama.continentLabel {
                    detail("Continent", continent)
                }
                detail("Latitude", formatCoord(panorama.location.lat))
                detail("Longitude", formatCoord(panorama.location.lng))
                detail("Attempts", "\(panorama.attempts)")
                detail("Image date", panorama.date ?? "Unknown")

                Button("Open in Google Maps") {
                    NSWorkspace.shared.open(mapsURL(for: panorama))
                }
                .padding(.top, 4)
            } else {
                Text("Pick a random place to begin.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .panelText()
    }
}

struct HistoryPanel: View {
    @EnvironmentObject private var model: WanderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                panelHeader("Visit History")
                Spacer()
                Text("\(model.history.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if model.history.isEmpty {
                Text("No random places yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.history) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
        .panelText()
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(entry.areaLabel)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                Spacer()
                Text(entry.visitedAt, style: .date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("\(formatCoord(entry.location.lat)), \(formatCoord(entry.location.lng))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                Button("Revisit") {
                    model.revisit(entry)
                }
                Button("Open Maps") {
                    NSWorkspace.shared.open(mapsURL(for: entry.panorama))
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: WanderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Keys")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Keys stay on this Mac. They are not bundled into releases.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("VITE_GOOGLE_MAPS_API_KEY")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("Maps JavaScript API key", text: $model.browserAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("GOOGLE_STREET_VIEW_METADATA_API_KEY")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("Street View metadata API key", text: $model.metadataAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Metadata API Request Count")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 16) {
                    requestMetric("Total", model.metadataRequestLimit > 0 ? formatCount(model.metadataRequestLimit) : "No limit")
                    requestMetric("Used", formatCount(model.metadataRequestsUsed))
                    requestMetric("Remaining", model.metadataRequestsRemaining.map(formatCount) ?? "No limit")
                }

                HStack(spacing: 10) {
                    TextField("Total request limit", value: $model.metadataRequestLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Text("0 means no limit")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Used Count") {
                        model.resetMetadataRequestUsage()
                    }
                }
            }

            HStack {
                Button("Import .env") {
                    model.importEnvFile()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func requestMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func panelHeader(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
}

private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        Text(value)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .textSelection(.enabled)
    }
}

private func formatCoord(_ value: Double) -> String {
    String(format: "%.5f", value)
}

private func formatCount(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

private func mapsURL(for panorama: Panorama) -> URL {
    var components = URLComponents(string: "https://www.google.com/maps/search/")!
    components.queryItems = [
        URLQueryItem(name: "api", value: "1"),
        URLQueryItem(name: "query", value: "\(panorama.location.lat),\(panorama.location.lng)")
    ]
    return components.url!
}

private struct PanelTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .tint(.white)
    }
}

private extension View {
    func panelText() -> some View {
        modifier(PanelTextModifier())
    }
}

struct OverlayButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(.white)
            .background(
                overlayFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(isActive ? 0.22 : 0))
            )
    }

    private func overlayFill(isPressed: Bool) -> Color {
        if isActive {
            return Color.white.opacity(isPressed ? 0.18 : 0.14)
        }
        return Color.white.opacity(isPressed ? 0.10 : 0.02)
    }
}

struct IconOverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(width: 34, height: 34)
            .foregroundStyle(.white)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.12 : 0.02),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}

struct PrimaryOverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .foregroundStyle(.white)
            .background(
                Color(red: 0.08, green: configuration.isPressed ? 0.36 : 0.46, blue: 0.39),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.14))
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.24), radius: 14, y: 8)
    }
}
