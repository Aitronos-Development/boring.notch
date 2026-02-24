//
//  VpnManager.swift
//  boringNotch
//
//  Polls the Hub HTTP API for VPN state and publishes it for the notch UI.
//  Follows the same pattern as TimeTrackingManager.
//

import Foundation

// MARK: - Data Models

struct SpeedSample: Codable, Identifiable {
    let downBytes: Double
    let upBytes: Double
    let timestampMs: UInt64

    var id: UInt64 { timestampMs }

    /// Download speed in Mbps
    var downMbps: Double { downBytes * 8 / 1_000_000 }
    /// Upload speed in Mbps
    var upMbps: Double { upBytes * 8 / 1_000_000 }

    enum CodingKeys: String, CodingKey {
        case downBytes = "down_bytes"
        case upBytes = "up_bytes"
        case timestampMs = "timestamp_ms"
    }
}

struct VpnProfileSummary: Codable, Identifiable {
    let id: String
    let name: String?
    let server: String?
    let status: String?
    let synced: Bool?

    /// Display name: prefer profile name, fall back to server, then ID
    var displayName: String {
        name ?? server ?? id
    }
}

struct VpnTrayState: Codable {
    let connected: Bool
    /// Granular status: "disconnected", "connecting", "connected", "disconnecting".
    let connectionStatus: String?
    let vpnServiceOnline: Bool
    /// "local" or "production" — determined by the Hub build mode.
    let environment: String?
    let serverName: String?
    let profileId: String?
    let iface: String?
    let downSpeedBytes: Double
    let upSpeedBytes: Double
    let sessionRecvBytes: UInt64
    let sessionSentBytes: UInt64
    let speedHistory: [SpeedSample]
    let profiles: [VpnProfileSummary]
    /// Whether the current public IP is on the organization's allowlist.
    let isAllowlisted: Bool
    /// The current public IP address (if detection succeeded).
    let publicIp: String?

    /// Whether VPN is in a transitional state (connecting/disconnecting).
    var isTransitional: Bool {
        connectionStatus == "connecting" || connectionStatus == "disconnecting"
    }

    enum CodingKeys: String, CodingKey {
        case connected
        case connectionStatus = "connection_status"
        case vpnServiceOnline = "vpn_service_online"
        case environment
        case serverName = "server_name"
        case profileId = "profile_id"
        case iface
        case downSpeedBytes = "down_speed_bytes"
        case upSpeedBytes = "up_speed_bytes"
        case sessionRecvBytes = "session_recv_bytes"
        case sessionSentBytes = "session_sent_bytes"
        case speedHistory = "speed_history"
        case profiles
        case isAllowlisted = "is_allowlisted"
        case publicIp = "public_ip"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connected = try container.decode(Bool.self, forKey: .connected)
        connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        vpnServiceOnline = try container.decode(Bool.self, forKey: .vpnServiceOnline)
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
        serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        profileId = try container.decodeIfPresent(String.self, forKey: .profileId)
        iface = try container.decodeIfPresent(String.self, forKey: .iface)
        downSpeedBytes = try container.decode(Double.self, forKey: .downSpeedBytes)
        upSpeedBytes = try container.decode(Double.self, forKey: .upSpeedBytes)
        sessionRecvBytes = try container.decode(UInt64.self, forKey: .sessionRecvBytes)
        sessionSentBytes = try container.decode(UInt64.self, forKey: .sessionSentBytes)
        speedHistory = try container.decode([SpeedSample].self, forKey: .speedHistory)
        profiles = try container.decode([VpnProfileSummary].self, forKey: .profiles)
        // Backwards-compatible: default to false/nil if Hub version doesn't include these fields
        isAllowlisted = try container.decodeIfPresent(Bool.self, forKey: .isAllowlisted) ?? false
        publicIp = try container.decodeIfPresent(String.self, forKey: .publicIp)
    }
}

// MARK: - Manager

@MainActor
final class VpnManager: ObservableObject {
    static let shared = VpnManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var serverName: String?
    @Published private(set) var profileId: String?
    @Published private(set) var downSpeedBytes: Double = 0
    @Published private(set) var upSpeedBytes: Double = 0
    @Published private(set) var sessionRecvBytes: UInt64 = 0
    @Published private(set) var sessionSentBytes: UInt64 = 0
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isConnecting: Bool = false
    @Published private(set) var isDisconnecting: Bool = false
    /// Granular connection status from Hub: "disconnected", "connecting", "connected", "disconnecting".
    @Published private(set) var connectionStatus: String = "disconnected"
    /// Whether the Hub API server is reachable (updated every poll cycle)
    @Published private(set) var serverReachable: Bool = false
    /// Whether the VPN service (Pritunl daemon) is running and has profiles
    @Published private(set) var vpnServiceOnline: Bool = false
    /// "local" or "production" — which Hub build the VPN is running against.
    @Published private(set) var environment: String = "unknown"
    @Published private(set) var speedHistory: [SpeedSample] = []
    @Published private(set) var profiles: [VpnProfileSummary] = []
    /// Whether the current public IP is on the organization's allowlist.
    @Published private(set) var isAllowlisted: Bool = false
    /// The current public IP address (if detection succeeded).
    @Published private(set) var publicIp: String?

    /// Selected profile ID for server picker. nil = "Auto" (recommended).
    @Published var selectedProfileId: String? = nil

    private var pollTimer: Timer?
    /// Fast-poll timer used during transitional states (1s interval).
    private var fastPollTimer: Timer?
    private var cachedPort: Int?
    private var currentTask: Task<Void, Never>?

    /// Download speed formatted as Mbps (e.g. "12.5")
    var downSpeedMbps: String {
        let mbps = downSpeedBytes * 8 / 1_000_000
        if mbps < 0.1 { return "0.0" }
        return String(format: "%.1f", mbps)
    }

    /// Upload speed formatted as Mbps (e.g. "4.2")
    var upSpeedMbps: String {
        let mbps = upSpeedBytes * 8 / 1_000_000
        if mbps < 0.1 { return "0.0" }
        return String(format: "%.1f", mbps)
    }

    /// Session received bytes formatted (e.g. "142 MB")
    var sessionRecvFormatted: String {
        formatBytes(sessionRecvBytes)
    }

    /// Session sent bytes formatted (e.g. "38 MB")
    var sessionSentFormatted: String {
        formatBytes(sessionSentBytes)
    }

    /// Peak download speed in the history (Mbps)
    var peakDownMbps: Double {
        speedHistory.map(\.downMbps).max() ?? 0
    }

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
        fastPollTimer?.invalidate()
    }

    // MARK: - Hub Port Discovery

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

    // MARK: - Polling

    private func startPolling() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.fetchVpnStatus()
        }
    }

    private func fetchVpnStatus() async {
        guard let port = await discoverHubPort() else {
            self.serverReachable = false
            return
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/vpn/status") else {
            self.serverReachable = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                self.serverReachable = false
                return
            }

            let decoder = JSONDecoder()
            let state = try decoder.decode(VpnTrayState.self, from: data)

            guard !Task.isCancelled else { return }

            self.serverReachable = true
            self.vpnServiceOnline = state.vpnServiceOnline
            self.environment = state.environment ?? "unknown"
            self.isConnected = state.connected
            self.serverName = state.serverName
            self.profileId = state.profileId
            self.downSpeedBytes = state.downSpeedBytes
            self.upSpeedBytes = state.upSpeedBytes
            self.sessionRecvBytes = state.sessionRecvBytes
            self.sessionSentBytes = state.sessionSentBytes
            self.speedHistory = state.speedHistory
            self.profiles = state.profiles
            self.isAllowlisted = state.isAllowlisted
            self.publicIp = state.publicIp
            self.isLoaded = true

            // Use server-reported connection status (authoritative)
            let status = state.connectionStatus ?? (state.connected ? "connected" : "disconnected")
            self.connectionStatus = status
            self.isConnecting = (status == "connecting")
            self.isDisconnecting = (status == "disconnecting")

            // Fast-poll during transitional states for responsive UI
            if state.isTransitional {
                startFastPolling()
            } else {
                stopFastPolling()
            }
        } catch {
            self.serverReachable = false
        }
    }

    /// Start fast-polling at 1s intervals during transitional states.
    private func startFastPolling() {
        guard fastPollTimer == nil else { return }
        fastPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// Stop fast-polling and return to normal 5s interval.
    private func stopFastPolling() {
        fastPollTimer?.invalidate()
        fastPollTimer = nil
    }

    // MARK: - Actions

    /// Connect to VPN. If profileId is specified, connects to that profile.
    /// If nil, connects to recommended (auto) profile.
    func connect(profileId: String? = nil) {
        let targetId = profileId ?? selectedProfileId
        isConnecting = true
        connectionStatus = "connecting"
        startFastPolling()
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else {
                self.isConnecting = false
                self.connectionStatus = "disconnected"
                self.stopFastPolling()
                return
            }

            let urlString: String
            if let id = targetId {
                urlString = "http://127.0.0.1:\(port)/hub/vpn/connect/\(id)"
            } else {
                urlString = "http://127.0.0.1:\(port)/hub/vpn/connect"
            }

            guard let url = URL(string: urlString) else {
                self.isConnecting = false
                self.connectionStatus = "disconnected"
                self.stopFastPolling()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)

            // Immediately refresh — Hub handler already updated tray state
            self.refresh()
        }
    }

    func disconnect() {
        isDisconnecting = true
        connectionStatus = "disconnecting"
        startFastPolling()
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else {
                self.isDisconnecting = false
                self.connectionStatus = "disconnected"
                self.stopFastPolling()
                return
            }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/vpn/disconnect") else {
                self.isDisconnecting = false
                self.connectionStatus = "disconnected"
                self.stopFastPolling()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)

            // Optimistic update
            self.isConnected = false
            self.serverName = nil
            self.downSpeedBytes = 0
            self.upSpeedBytes = 0
            self.sessionRecvBytes = 0
            self.sessionSentBytes = 0
            self.speedHistory = []

            // Immediately refresh — Hub handler already updated tray state
            self.refresh()
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1_000
        let mb = kb / 1_000
        let gb = mb / 1_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }
}
