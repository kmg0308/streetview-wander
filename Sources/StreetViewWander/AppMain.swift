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
                .frame(minWidth: 1040, minHeight: 700)
                .task {
                    updates.startAutoChecks()
                    await model.refreshSamplerConfig()
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
        VStack(spacing: 0) {
            appHeader
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)

            contentArea
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 22)
        }
        .foregroundStyle(WanderTheme.primaryText)
        .background {
            WanderBackdrop()
                .ignoresSafeArea()
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $updates.isSheetPresented) {
            UpdateSheetView()
                .environmentObject(updates)
        }
    }

    private var appHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    WanderControlChrome(cornerRadius: WanderTheme.compactControlRadius)
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.accent)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("StreetView Wander")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WanderTheme.primaryText)
                    Text(headerSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WanderTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(minWidth: 155, alignment: .leading)
            }

            Spacer(minLength: 8)

            panelSelector
                .frame(width: 300)

            Button {
                model.isSettingsPresented = true
            } label: {
                Image(systemName: "key")
            }
            .buttonStyle(WanderIconButtonStyle(prominent: !model.hasBrowserAPIKey || !model.hasMetadataAPIKey))
            .help("API key settings")
            .accessibilityLabel("API key settings")

            metadataUsageBadge

            Button {
                if updates.updateLabel != nil {
                    updates.updateNow()
                } else {
                    updates.isSheetPresented = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: updates.updateLabel == nil ? "arrow.down.circle" : "arrow.down.circle.fill")
                    Text(updates.updateLabel == nil ? "Updates" : "Update")
                }
            }
            .buttonStyle(WanderPillButtonStyle(prominent: updates.updateLabel != nil))
            .help(updates.updateLabel ?? "Updates")
            .accessibilityLabel(updates.updateLabel ?? "Updates")

            Button {
                model.randomPlace()
            } label: {
                Label(model.isLoading ? "Finding..." : "Random place", systemImage: "shuffle")
            }
            .disabled(model.isLoading)
            .buttonStyle(WanderPillButtonStyle(prominent: true))
            .accessibilityLabel(model.isLoading ? "Finding random place" : "Random place")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .wanderSurface(elevated: true, radius: 18)
    }

    private var panelSelector: some View {
        HStack(spacing: 4) {
            panelButton(.history, title: "History", icon: "clock.arrow.circlepath")
            panelButton(.details, title: "Details", icon: "info.circle")
            panelButton(.scope, title: "Scope", icon: "scope")
        }
        .padding(3)
        .frame(height: WanderTheme.buttonHeight)
        .background {
            WanderControlChrome()
        }
    }

    private func panelButton(_ panel: WanderModel.Panel, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                model.activePanel = model.activePanel == panel ? .none : panel
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(WanderSegmentButtonStyle(selected: model.activePanel == panel))
        .accessibilityLabel(title)
    }

    private var headerSubtitle: String {
        if let panorama = model.panorama {
            if let scene = panorama.sceneKind?.label {
                return "\(panorama.areaLabel) - \(scene)"
            }
            return panorama.areaLabel
        }
        return "\(model.selectedScopeLabel) scope"
    }

    private var contentArea: some View {
        HStack(alignment: .top, spacing: 18) {
            mapStage

            if model.activePanel != .none {
                sidePanel
                    .frame(width: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: panelIsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelIsVisible: Bool {
        model.activePanel != .none
    }

    private var mapStage: some View {
        ZStack(alignment: .bottomLeading) {
            StreetViewWebView(
                panorama: model.panorama,
                browserAPIKey: model.browserAPIKey
            )
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.cardRadius, style: .continuous))

            bottomStatus
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wanderSurface(elevated: true)
    }

    private var bottomStatus: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.primaryText)
                        Text(model.errorText ?? model.statusText)
                            .lineLimit(2)
                            .font(.system(size: 12))
                            .foregroundStyle(model.errorText == nil ? WanderTheme.secondaryText : WanderTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)

                    if !model.hasBrowserAPIKey || !model.hasMetadataAPIKey {
                        Button {
                            model.isSettingsPresented = true
                        } label: {
                            Label("Add API Keys", systemImage: "key")
                        }
                        .buttonStyle(WanderPillButtonStyle(prominent: true))
                        .accessibilityLabel("Add API Keys")
                    }
                }

                if let reason = model.selectionReasonSummary, model.errorText == nil {
                    Text(reason)
                        .lineLimit(2)
                        .font(.system(size: 12))
                        .foregroundStyle(WanderTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.panorama != nil, !model.isLoading {
                    feedbackBar
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 660, alignment: .leading)
        .wanderSurface(elevated: true)
    }

    private var statusTitle: String {
        if model.errorText != nil {
            return "Needs attention"
        }
        if model.isLoading {
            return "Finding panorama"
        }
        if model.panorama != nil {
            return "Current start"
        }
        return "Ready"
    }

    private var statusIcon: String {
        if model.errorText != nil {
            return "exclamationmark.triangle"
        }
        if model.isLoading {
            return "arrow.triangle.2.circlepath"
        }
        if model.panorama != nil {
            return "location.viewfinder"
        }
        return "sparkles"
    }

    private var statusTint: Color {
        if model.errorText != nil {
            return WanderTheme.warning
        }
        if model.isLoading || model.panorama != nil {
            return WanderTheme.accent
        }
        return WanderTheme.secondaryText
    }

    private var feedbackBar: some View {
        HStack(spacing: 6) {
            feedbackButton(.liked, icon: "hand.thumbsup")
            feedbackButton(.tooSimilar, icon: "square.on.square")
            feedbackButton(.tooManyRoads, icon: "road.lanes")
            feedbackButton(.moreCity, icon: "building.2")
        }
    }

    private func feedbackButton(_ kind: PlaceFeedbackKind, icon: String) -> some View {
        Button {
            model.recordFeedback(kind)
        } label: {
            Label(kind.label, systemImage: icon)
        }
        .buttonStyle(WanderPillButtonStyle(selected: model.hasFeedback(kind)))
        .help(kind.label)
        .accessibilityLabel(kind.label)
    }

    private var metadataUsageBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(metadataUsageBadgeText)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(WanderTheme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: WanderTheme.buttonHeight)
        .background {
            WanderControlChrome(cornerRadius: WanderTheme.controlRadius)
        }
        .help(metadataUsageStatus)
        .accessibilityLabel(metadataUsageStatus)
    }

    private var metadataUsageStatus: String {
        if let remaining = model.metadataRequestsRemaining {
            return "Metadata checks \(formatCount(model.metadataRequestsUsed))/\(formatCount(model.metadataRequestLimit)) · \(formatCount(remaining)) left"
        }
        return "Metadata checks \(formatCount(model.metadataRequestsUsed)) · no limit"
    }

    private var metadataUsageBadgeText: String {
        if model.metadataRequestLimit > 0 {
            return "Checks \(formatCount(model.metadataRequestsUsed))/\(formatCount(model.metadataRequestLimit))"
        }
        return "Checks \(formatCount(model.metadataRequestsUsed))"
    }

    private var sidePanel: some View {
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
        .padding(16)
        .frame(maxHeight: .infinity)
        .wanderSurface(elevated: true)
    }
}

struct ScopePanel: View {
    @EnvironmentObject private var model: WanderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("Random Scope")

            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    selectionButton("Worldwide", isSelected: model.selectedContinentId.isEmpty) {
                        model.selectedContinentId = ""
                    }
                    ForEach(model.locationOptions.continents) { continent in
                        selectionButton("\(continent.label) (\(continent.countryCount))", isSelected: model.selectedContinentId == continent.id) {
                            model.selectedContinentId = continent.id
                        }
                    }
                } label: {
                    WanderFilterMenuLabel(title: "Continent", value: selectedContinentLabel)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Continent")

                Menu {
                    selectionButton("All countries", isSelected: model.selectedCountryId.isEmpty) {
                        model.selectedCountryId = ""
                    }
                    ForEach(model.filteredCountries) { country in
                        selectionButton(country.label, isSelected: model.selectedCountryId == country.id) {
                            model.selectedCountryId = country.id
                        }
                    }
                } label: {
                    WanderFilterMenuLabel(title: "Country", value: selectedCountryLabel)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Country")
            }

            HStack(spacing: 8) {
                scopeMetric("Active", model.selectedScopeLabel)
                scopeMetric("Countries", formatCount(model.filteredCountries.count))
            }
            .padding(14)
            .wanderSurface()

            Button {
                model.clearScope()
            } label: {
                Label("Clear Scope", systemImage: "xmark.circle")
            }
            .buttonStyle(WanderPillButtonStyle())
            .accessibilityLabel("Clear Scope")

            Spacer()
        }
        .panelText()
    }

    private var selectedContinentLabel: String {
        model.locationOptions.continents.first(where: { $0.id == model.selectedContinentId })?.label ?? "Worldwide"
    }

    private var selectedCountryLabel: String {
        model.locationOptions.countries.first(where: { $0.id == model.selectedCountryId })?.label ?? "All countries"
    }

    @ViewBuilder
    private func selectionButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func scopeMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WanderTheme.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailsPanel: View {
    @EnvironmentObject private var model: WanderModel

    var body: some View {
        ScrollView {
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
                    if let sceneKind = panorama.sceneKind {
                        detail("Search mix", sceneKind.label)
                    }
                    detail("Latitude", formatCoord(panorama.location.lat))
                    detail("Longitude", formatCoord(panorama.location.lng))
                    detail("Requested", "\(formatCoord(panorama.requestedLocation.lat)), \(formatCoord(panorama.requestedLocation.lng))")
                    detail(
                        "Request distance",
                        formatDistance(
                            SearchDensityTier.distanceMeters(
                                from: panorama.requestedLocation,
                                to: panorama.location
                            )
                        )
                    )
                    detail("Metadata checks", "\(panorama.attempts)")
                    detail("Image date", panorama.date ?? "Unknown")
                    detail("Sampler config", model.samplerConfigSourceLabel)

                    if let reason = panorama.selectionReasonSummary {
                        detail("Selection reason", reason)
                    }
                    if !model.selectionReasonDetails.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reason details")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WanderTheme.secondaryText)
                            ForEach(Array(model.selectionReasonDetails.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.system(size: 12))
                                    .foregroundStyle(WanderTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wanderSurface()
                    }

                    Button {
                        NSWorkspace.shared.open(mapsURL(for: panorama))
                    } label: {
                        Label("Open in Google Maps", systemImage: "map")
                    }
                    .buttonStyle(WanderPillButtonStyle())
                    .accessibilityLabel("Open in Google Maps")
                    .padding(.top, 4)
                } else {
                    Text("Pick a random place to begin.")
                        .foregroundStyle(WanderTheme.secondaryText)
                }

                Spacer()
            }
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
                    .foregroundStyle(WanderTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background {
                        WanderControlChrome(cornerRadius: WanderTheme.compactControlRadius)
                    }
            }

            if model.history.isEmpty {
                Text("No random places yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(WanderTheme.secondaryText)
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
                    .foregroundStyle(WanderTheme.primaryText)
                Spacer()
                Text(entry.visitedAt, style: .date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WanderTheme.tertiaryText)
            }

            Text("\(formatCoord(entry.location.lat)), \(formatCoord(entry.location.lng))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WanderTheme.secondaryText)

            HStack(spacing: 8) {
                Button {
                    model.revisit(entry)
                } label: {
                    Label("Revisit", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(WanderPillButtonStyle())
                .accessibilityLabel("Revisit")

                Button {
                    NSWorkspace.shared.open(mapsURL(for: entry.panorama))
                } label: {
                    Label("Open Maps", systemImage: "map")
                }
                .buttonStyle(WanderPillButtonStyle())
                .accessibilityLabel("Open Maps")
            }
        }
        .padding(12)
        .wanderSurface()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: WanderModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftBrowserAPIKey = ""
    @State private var draftMetadataAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("API Keys")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WanderTheme.primaryText)
                    Text("Keys stay on this Mac. They are not bundled into releases.")
                        .font(.system(size: 12))
                        .foregroundStyle(WanderTheme.secondaryText)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(WanderCompactIconButtonStyle())
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 10) {
                keyField(
                    "VITE_GOOGLE_MAPS_API_KEY",
                    placeholder: "Maps JavaScript API key",
                    text: $draftBrowserAPIKey
                )
                keyField(
                    "GOOGLE_STREET_VIEW_METADATA_API_KEY",
                    placeholder: "Street View metadata API key",
                    text: $draftMetadataAPIKey
                )
            }
            .padding(14)
            .wanderSurface()

            VStack(alignment: .leading, spacing: 10) {
                Text("Metadata Check Count")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.primaryText)

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
                        .foregroundStyle(WanderTheme.secondaryText)
                    Spacer()
                    Button {
                        model.resetMetadataRequestUsage()
                    } label: {
                        Label("Reset Used Count", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(WanderPillButtonStyle())
                    .accessibilityLabel("Reset Used Count")
                }
            }
            .padding(14)
            .wanderSurface()

            VStack(alignment: .leading, spacing: 10) {
                Text("Feedback")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.primaryText)

                HStack(spacing: 10) {
                    requestMetric("Signals", formatCount(model.feedbackCount))
                    requestMetric("Config", model.samplerConfigSourceLabel)
                    Spacer()
                    Button {
                        model.resetFeedback()
                    } label: {
                        Label("Reset Feedback", systemImage: "trash")
                    }
                    .buttonStyle(WanderPillButtonStyle())
                    .accessibilityLabel("Reset Feedback")
                }
            }
            .padding(14)
            .wanderSurface()

            HStack {
                Button {
                    if model.importEnvFile() {
                        resetDraftKeys()
                    }
                } label: {
                    Label("Import .env", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WanderPillButtonStyle())
                .accessibilityLabel("Import .env")
                Spacer()
                Button {
                    model.saveAPIKeys(browser: draftBrowserAPIKey, metadata: draftMetadataAPIKey)
                    dismiss()
                } label: {
                    Text("Done")
                }
                .buttonStyle(WanderPillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Done")
            }
        }
        .padding(20)
        .frame(width: 540)
        .foregroundStyle(WanderTheme.primaryText)
        .background {
            WanderBackdrop()
        }
        .onAppear(perform: resetDraftKeys)
    }

    private func keyField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WanderTheme.secondaryText)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .tint(WanderTheme.accent)
        }
    }

    private func resetDraftKeys() {
        model.loadAPIKeysForEditing()
        draftBrowserAPIKey = model.browserAPIKey
        draftMetadataAPIKey = model.metadataAPIKey
    }

    private func requestMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WanderTheme.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func panelHeader(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(WanderTheme.primaryText)
}

@MainActor private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WanderTheme.secondaryText)
        Text(value)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WanderTheme.primaryText)
            .textSelection(.enabled)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .wanderSurface()
}

private func formatCoord(_ value: Double) -> String {
    String(format: "%.5f", value)
}

private func formatCount(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

private func formatDistance(_ meters: Double) -> String {
    if meters >= 1_000 {
        return String(format: "%.1f km", meters / 1_000)
    }
    return String(format: "%.0f m", meters)
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
            .foregroundStyle(WanderTheme.primaryText)
            .tint(WanderTheme.accent)
    }
}

private extension View {
    func panelText() -> some View {
        modifier(PanelTextModifier())
    }
}
