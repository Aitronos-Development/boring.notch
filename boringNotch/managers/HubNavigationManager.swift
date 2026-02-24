//
//  HubNavigationManager.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//

import Foundation

// MARK: - Data Models

struct HubPage: Codable, Identifiable {
    let label: String
    let path: String
    let icon: String

    var id: String { path }
}

// MARK: - Manager

@MainActor
final class HubNavigationManager: ObservableObject {
    static let shared = HubNavigationManager()

    @Published private(set) var pages: [HubPage] = []
    @Published private(set) var isLoaded: Bool = false

    private init() {
        Task { await fetchPages() }
    }

    // MARK: - Hub Port Discovery (shared with NotificationManager pattern)

    private var cachedPort: Int?

    /// Public accessor for port discovery — used by NotchShareMenu
    func resolvePort() async -> Int? {
        return await discoverHubPort()
    }

    private func discoverHubPort() async -> Int? {
        if let port = cachedPort, await probePort(port) {
            return port
        }
        for port in 3001...3010 {
            if await probePort(port) {
                cachedPort = port
                return port
            }
        }
        cachedPort = nil
        return nil
    }

    private func probePort(_ port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return false }
        return true
    }

    // MARK: - Fetch Pages

    private func fetchPages() async {
        guard let port = await discoverHubPort() else {
            // Use fallback pages if Hub is not available
            pages = Self.fallbackPages
            isLoaded = true
            return
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/navigation/pages") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                pages = Self.fallbackPages
                isLoaded = true
                return
            }
            pages = try JSONDecoder().decode([HubPage].self, from: data)
            isLoaded = true
        } catch {
            pages = Self.fallbackPages
            isLoaded = true
        }
    }

    /// Fallback pages when Hub HTTP server is not reachable
    private static let fallbackPages: [HubPage] = [
        HubPage(label: "Secure Paste", path: "/secure-paste", icon: "lock.fill"),
        HubPage(label: "VPN", path: "/vpn", icon: "shield.fill"),
        HubPage(label: "Device Manager", path: "/device-manager", icon: "desktopcomputer"),
        HubPage(label: "Speed Test", path: "/speed-test", icon: "gauge.medium"),
        HubPage(label: "People", path: "/people", icon: "person.2.fill"),
        HubPage(label: "Time Tracking", path: "/time-tracking", icon: "clock.fill"),
        HubPage(label: "Announcements", path: "/announcements", icon: "megaphone.fill"),
        HubPage(label: "Requests", path: "/requests", icon: "doc.text.fill"),
    ]

    // MARK: - Actions

    /// Navigate the Hub window to a specific page path
    func navigateToPage(_ path: String) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/navigate") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["path": path])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Toggle the Hub main window visibility (show/hide)
    func toggleHubWindow() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/toggle") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Open the Fleet Dashboard URL in the default browser
    func openFleetDashboard() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/fleet-dashboard") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Show the Hub window (bring to front)
    func showHubWindow() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/show") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
