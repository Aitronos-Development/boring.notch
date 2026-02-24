//
//  TimeSlotSummaryManager.swift
//  boringNotch
//
//  Polls the Hub HTTP API for time tracking slot summary and publishes it for the notch UI.
//  Follows the same pattern as TimeTrackingManager.
//

import Foundation

// MARK: - Data Models

struct PendingSlotInfo: Codable {
    let startTime: String
    let endTime: String
    let durationSeconds: UInt64
    let apps: [String]
    let suggestedTaskName: String?
    let isMeeting: Bool

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case apps
        case suggestedTaskName = "suggested_task_name"
        case isMeeting = "is_meeting"
    }
}

struct TimeTrackingSummaryResponse: Codable {
    let date: String
    let pendingCount: UInt32
    let pendingSeconds: UInt64
    let loggedCount: UInt32
    let loggedSeconds: UInt64
    let skippedCount: UInt32
    let freeTimeCount: UInt32
    let totalCount: UInt32
    let nextPending: PendingSlotInfo?

    enum CodingKeys: String, CodingKey {
        case date
        case pendingCount = "pending_count"
        case pendingSeconds = "pending_seconds"
        case loggedCount = "logged_count"
        case loggedSeconds = "logged_seconds"
        case skippedCount = "skipped_count"
        case freeTimeCount = "free_time_count"
        case totalCount = "total_count"
        case nextPending = "next_pending"
    }
}

// MARK: - Manager

@MainActor
final class TimeSlotSummaryManager: ObservableObject {
    static let shared = TimeSlotSummaryManager()

    @Published private(set) var pendingCount: UInt32 = 0
    @Published private(set) var pendingSeconds: UInt64 = 0
    @Published private(set) var loggedCount: UInt32 = 0
    @Published private(set) var loggedSeconds: UInt64 = 0
    @Published private(set) var totalCount: UInt32 = 0
    @Published private(set) var nextPendingSlot: PendingSlotInfo?
    @Published private(set) var isLoaded: Bool = false

    var hasPendingSlots: Bool { pendingCount > 0 }

    /// Formatted pending time: "1h 30m" or "45m"
    var pendingFormatted: String {
        let h = pendingSeconds / 3600
        let m = (pendingSeconds % 3600) / 60
        if h > 0 {
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(m)m"
    }

    /// Formatted logged time: "4h 15m" or "2h"
    var loggedFormatted: String {
        let h = loggedSeconds / 3600
        let m = (loggedSeconds % 3600) / 60
        if h > 0 {
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(m)m"
    }

    private var pollTimer: Timer?
    private var cachedPort: Int?
    private var currentTask: Task<Void, Never>?

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Hub Port Discovery

    func discoverHubPort() async -> Int? {
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.fetchSummary()
        }
    }

    private func fetchSummary() async {
        guard let port = await discoverHubPort() else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/summary") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            let summary = try decoder.decode(TimeTrackingSummaryResponse.self, from: data)

            guard !Task.isCancelled else { return }

            self.pendingCount = summary.pendingCount
            self.pendingSeconds = summary.pendingSeconds
            self.loggedCount = summary.loggedCount
            self.loggedSeconds = summary.loggedSeconds
            self.totalCount = summary.totalCount
            self.nextPendingSlot = summary.nextPending
            self.isLoaded = true
        } catch {
            // Silently ignore — Hub may not be running or time tracking not active
        }
    }
}
