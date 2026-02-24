//
//  TeamPresenceManager.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-17.
//

import Combine
import Foundation

// MARK: - Data Models

enum PresenceStatus: String, Codable, CaseIterable {
    case available
    case busy
    case doNotDisturb = "do_not_disturb"
    case beRightBack = "be_right_back"
    case appearAway = "appear_away"
    case appearOffline = "appear_offline"

    var label: String {
        switch self {
        case .available: return "Available"
        case .busy: return "Busy"
        case .doNotDisturb: return "Do Not Disturb"
        case .beRightBack: return "Be Right Back"
        case .appearAway: return "Away"
        case .appearOffline: return "Offline"
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .busy: return "minus.circle.fill"
        case .doNotDisturb: return "bell.slash.circle.fill"
        case .beRightBack: return "clock.fill"
        case .appearAway: return "moon.circle.fill"
        case .appearOffline: return "circle"
        }
    }

    var dotColor: String {
        switch self {
        case .available: return "green"
        case .busy: return "red"
        case .doNotDisturb: return "red"
        case .beRightBack: return "yellow"
        case .appearAway: return "yellow"
        case .appearOffline: return "gray"
        }
    }

    var isOnline: Bool {
        switch self {
        case .available, .busy, .doNotDisturb, .beRightBack:
            return true
        case .appearAway, .appearOffline:
            return false
        }
    }
}

struct TeamMember: Codable, Identifiable {
    let email: String
    let name: String
    let picture: String?
    let department: String?
    let jobTitle: String?
    let personalEmail: String?
    let appleId: String?
    let deviceOnline: Bool
    let deviceName: String?
    let lastSeen: String?
    let primaryIp: String?
    let location: String?
    let presenceStatus: PresenceStatus
    let statusText: String?
    let sharingEnabled: Bool

    var id: String { email }

    enum CodingKeys: String, CodingKey {
        case email, name, department, location
        case picture = "pictureUrl"
        case jobTitle = "jobTitle"
        case personalEmail = "personalEmail"
        case appleId = "appleId"
        case deviceOnline = "deviceOnline"
        case deviceName = "deviceName"
        case lastSeen = "lastSeen"
        case primaryIp = "primaryIp"
        case presenceStatus = "presenceStatus"
        case statusText = "statusText"
        case sharingEnabled = "sharingEnabled"
    }
}

struct TeamPresenceSummary: Codable {
    let totalMembers: Int
    let onlineCount: Int
    let currentUserStatus: String
    let currentUserStatusText: String?
    let members: [TeamMember]

    enum CodingKeys: String, CodingKey {
        case totalMembers = "totalMembers"
        case onlineCount = "onlineCount"
        case currentUserStatus = "currentUserStatus"
        case currentUserStatusText = "currentUserStatusText"
        case members
    }
}

// MARK: - Manager

@MainActor
final class TeamPresenceManager: ObservableObject {
    static let shared = TeamPresenceManager()

    @Published private(set) var onlineCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var currentUserStatus: PresenceStatus = .available
    @Published private(set) var currentUserStatusText: String?
    @Published private(set) var members: [TeamMember] = []
    @Published private(set) var isLoaded: Bool = false

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 15
    private var currentTask: Task<Void, Never>?

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Hub Port Discovery

    /// Cached discovered port (avoids re-scanning every poll)
    private var cachedPort: Int?

    /// Discover Hub server port by probing localhost:3001-3010.
    /// The Hub binds to the first available port in this range, so we check each one
    /// for a valid `/hub/status` response. This avoids filesystem access which fails
    /// inside App Sandbox.
    private func discoverHubPort() async -> Int? {
        // Return cached port if still reachable
        if let port = cachedPort,
           await probePort(port) {
            return port
        }

        // Scan port range
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
        // Fetch immediately
        refresh()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.fetchPresence()
        }
    }

    private func fetchPresence() async {
        guard let port = await discoverHubPort() else { return }
        let urlString = "http://127.0.0.1:\(port)/hub/team/presence"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            let summary = try decoder.decode(TeamPresenceSummary.self, from: data)

            guard !Task.isCancelled else { return }

            self.totalCount = summary.totalMembers
            self.onlineCount = summary.onlineCount
            self.currentUserStatus = PresenceStatus(rawValue: summary.currentUserStatus) ?? .available
            self.currentUserStatusText = summary.currentUserStatusText
            self.members = summary.members.sorted { a, b in
                if a.presenceStatus.isOnline != b.presenceStatus.isOnline {
                    return a.presenceStatus.isOnline
                }
                return a.name < b.name
            }
            self.isLoaded = true
        } catch {
            // Silently ignore — Hub may not be running
        }
    }

    // MARK: - Messaging & Contacts

    /// Open Messages.app compose window for a recipient
    func openMessage(to email: String) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/messaging/imessage") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["recipient": email])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Start a FaceTime video call with a recipient (Apple ID)
    func openFaceTime(to recipient: String) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/messaging/facetime") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["recipient": recipient])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Start a FaceTime audio call with a recipient (Apple ID)
    func openFaceTimeAudio(to recipient: String) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/messaging/facetime-audio") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["recipient": recipient])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Open mail compose window for a recipient
    func openEmail(to email: String) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/messaging/email") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["recipient": email])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Download a team member to macOS Contacts (skips if already present)
    func downloadContact(_ member: TeamMember) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/contacts/download") else { return }

            let nameParts = member.name.split(separator: " ", maxSplits: 1)
            let firstName = String(nameParts.first ?? "")
            let lastName = nameParts.count > 1 ? String(nameParts[1]) : ""

            struct ContactDownload: Encodable {
                let firstName: String
                let lastName: String
                let email: String
                let personalEmail: String?
                let appleId: String?
                let jobTitle: String?
                let department: String?
            }

            let contact = ContactDownload(
                firstName: firstName,
                lastName: lastName,
                email: member.email,
                personalEmail: member.personalEmail,
                appleId: member.appleId,
                jobTitle: member.jobTitle,
                department: member.department
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(contact)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Result of sending a message
    struct SendResult {
        let success: Bool
        /// The password used for the encrypted paste, if any
        let secureBinPassword: String?
    }

    /// Send a message to a team member via the Hub server
    func sendMessage(
        to member: TeamMember,
        text: String,
        secureBin: Bool,
        attachmentPath: String?,
        expire: String = "1day",
        burnAfterReading: Bool = true,
        password: String? = nil
    ) async -> SendResult {
        guard let appleId = member.appleId, !appleId.isEmpty else {
            return SendResult(success: false, secureBinPassword: nil)
        }
        guard let port = await discoverHubPort() else {
            return SendResult(success: false, secureBinPassword: nil)
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/messaging/send") else {
            return SendResult(success: false, secureBinPassword: nil)
        }

        struct SendBody: Encodable {
            let recipient: String
            let message: String
            let secure_bin: Bool
            let attachment_path: String?
            let expire: String
            let burn_after_reading: Bool
            let password: String?
        }

        let body = SendBody(
            recipient: appleId,
            message: text,
            secure_bin: secureBin,
            attachment_path: attachmentPath,
            expire: expire,
            burn_after_reading: burnAfterReading,
            password: password
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        struct SendResponse: Decodable {
            let status: String
            let secure_bin_url: String?
            let secure_bin_password: String?
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return SendResult(success: false, secureBinPassword: nil)
        }

        let decoded = try? JSONDecoder().decode(SendResponse.self, from: data)
        return SendResult(success: true, secureBinPassword: decoded?.secure_bin_password)
    }

    // MARK: - Status Updates

    func setStatus(_ status: PresenceStatus, text: String? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            let urlString = "http://127.0.0.1:\(port)/hub/team/status"
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            struct SetStatusBody: Encodable {
                let status: PresenceStatus
                let status_text: String?
            }

            let body = SetStatusBody(status: status, status_text: text)
            request.httpBody = try? JSONEncoder().encode(body)

            _ = try? await URLSession.shared.data(for: request)

            // Optimistic update
            self.currentUserStatus = status
            self.currentUserStatusText = text

            // Refresh to get full update
            self.refresh()
        }
    }
}
