//
//  NotificationManager.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//  Updated: 2026-02-23 — modal routing + three notification modes
//

import Foundation

// MARK: - Data Models

struct CachedNotification: Codable, Identifiable {
    let id: String
    let notificationType: String
    let title: String
    let body: String
    let link: String
    let senderName: String
    let priority: String
    let effect: String
    let bodyFormat: String
    let createdAt: String
    let expiresAt: String?
    let sticky: Bool
    let modal: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case notificationType = "type"
        case title, body, link
        case senderName = "sender_name"
        case priority, effect
        case bodyFormat = "body_format"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sticky, modal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        notificationType = try c.decode(String.self, forKey: .notificationType)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
        effect = try c.decodeIfPresent(String.self, forKey: .effect) ?? ""
        bodyFormat = try c.decodeIfPresent(String.self, forKey: .bodyFormat) ?? "plain"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        sticky = try c.decodeIfPresent(Bool.self, forKey: .sticky) ?? false
        modal = try c.decodeIfPresent(Bool.self, forKey: .modal) ?? false
    }

    var isUrgent: Bool { priority == "urgent" }
    var hasEffect: Bool { !effect.isEmpty }
    var isHTML: Bool { bodyFormat == "html" }
    var isSticky: Bool { sticky || isUrgent }
    var isModal: Bool { modal }
}

struct NotificationCache: Codable {
    let notifications: [CachedNotification]
    let unreadCount: UInt32

    enum CodingKeys: String, CodingKey {
        case notifications
        case unreadCount = "unread_count"
    }
}

// MARK: - Manager

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var notifications: [CachedNotification] = []
    @Published private(set) var unreadCount: UInt32 = 0
    @Published private(set) var currentBanner: CachedNotification?
    @Published private(set) var isLoaded: Bool = false

    /// Set when a new notification arrives — triggers Notch open animation
    @Published var newlyArrivedNotification: CachedNotification?

    /// True when the detail view should be shown (after clicking the banner)
    @Published var showingDetail: Bool = false
    @Published var detailNotification: CachedNotification?

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 3
    private var currentTask: Task<Void, Never>?

    /// IDs dismissed in this session (prevents re-showing before backend sync)
    private var locallyDismissedIds: Set<String> = []

    /// IDs we've already seen — used to detect new arrivals
    private var knownIds: Set<String> = []

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Hub Port Discovery

    private var cachedPort: Int?

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
            await self.fetchNotifications()
        }
    }

    private func fetchNotifications() async {
        guard let port = await discoverHubPort() else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/notifications") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            let cache = try decoder.decode(NotificationCache.self, from: data)
            guard !Task.isCancelled else { return }

            // Filter out locally dismissed notifications
            let filtered = cache.notifications.filter { !locallyDismissedIds.contains($0.id) }
            self.notifications = filtered
            self.unreadCount = UInt32(filtered.count)

            // Detect newly arrived notifications (not in knownIds)
            let newNotifications = filtered.filter { !knownIds.contains($0.id) }
            knownIds = Set(filtered.map { $0.id })

            // On first load, don't trigger arrival animation
            if !isLoaded {
                isLoaded = true
                // Set initial banner without triggering toast
                currentBanner = filtered.first
            } else if let newest = newNotifications.first {
                // New notification arrived — route to modal or compact toast
                NSLog("[Notch] New notification: %@ modal=%d isModal=%d type=%@", newest.title, newest.modal ? 1 : 0, newest.isModal ? 1 : 0, newest.notificationType)
                newlyArrivedNotification = newest
                if newest.isModal {
                    NSLog("[Notch] → Routing to MODAL window controller")
                    ModalNotificationWindowController.shared.show(newest)
                } else {
                    NSLog("[Notch] → Routing to compact toast window controller")
                    NotificationToastWindowController.shared.show(newest)
                }
            }

            // Advance current banner
            if let current = currentBanner {
                if !filtered.contains(where: { $0.id == current.id }) {
                    currentBanner = filtered.first
                }
            } else {
                currentBanner = filtered.first
            }
        } catch {
            // Silently ignore — Hub may not be running
        }
    }

    // MARK: - Actions

    /// Dismiss a notification (remove from banner, notify backend)
    func dismiss(_ id: String) {
        locallyDismissedIds.insert(id)
        notifications.removeAll { $0.id == id }
        unreadCount = UInt32(notifications.count)

        // Advance banner to next notification
        if currentBanner?.id == id {
            currentBanner = notifications.first
        }

        // Notify backend asynchronously
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/notifications/\(id)/dismiss") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["user_id": ""])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Clear the newly arrived notification flag
    func clearNewArrival() {
        newlyArrivedNotification = nil
    }

    /// Show the detail view for a notification
    func showDetail(for notification: CachedNotification) {
        detailNotification = notification
        showingDetail = true
    }

    /// Close the detail view
    func closeDetail() {
        showingDetail = false
        detailNotification = nil
    }

    /// Open a notification: show Hub window, navigate to the link path, then dismiss
    func openNotification(_ id: String) {
        // Look up notification from all sources
        let notification: CachedNotification? = notifications.first(where: { $0.id == id })
            ?? (currentBanner?.id == id ? currentBanner : nil)

        let link: String
        if let n = notification {
            link = n.link.isEmpty ? "/announcements" : n.link
        } else {
            // Notification already removed — still show Hub
            print("[Notch] openNotification: notification \(id) not in list, defaulting to /announcements")
            link = "/announcements"
        }

        // Show Hub window and navigate
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else {
                print("[Notch] openNotification: could not discover Hub port")
                return
            }

            // First ensure the Hub window is visible
            if let showUrl = URL(string: "http://127.0.0.1:\(port)/hub/window/show") {
                var showReq = URLRequest(url: showUrl)
                showReq.httpMethod = "POST"
                showReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: showReq)
            }

            // Then navigate to the notification link
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/navigate") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["path": link])

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("[Notch] openNotification: Hub returned status \(httpResponse.statusCode)")
                }
            } catch {
                print("[Notch] openNotification: failed to reach Hub: \(error.localizedDescription)")
            }
        }

        dismiss(id)
    }
}
