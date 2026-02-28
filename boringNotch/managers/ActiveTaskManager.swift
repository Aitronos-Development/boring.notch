//
//  ActiveTaskManager.swift
//  boringNotch
//
//  Polls the Hub HTTP API for the active task state ("I'm working on X").
//  When an active task is set, new detected sessions auto-log to it.
//  Provides start/stop/change actions for the Notch UI.
//
//  State is mirrored into UserDefaults so the Notch can show the active task
//  instantly on launch — before the first HTTP poll completes.
//

import Foundation

// MARK: - Data Model

struct ActiveTaskState: Codable {
    let taskId: String
    let taskName: String
    let taskColor: String?
    let source: String // "hub" or "clickup"
    let startedAt: Int64 // Unix ms

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskName = "task_name"
        case taskColor = "task_color"
        case source
        case startedAt = "started_at"
    }
}

// MARK: - UserDefaults persistence key

private let kActiveTaskCacheKey = "cachedActiveTask"

// MARK: - Manager

@MainActor
final class ActiveTaskManager: ObservableObject {
    static let shared = ActiveTaskManager()

    @Published private(set) var activeTask: ActiveTaskState?
    @Published private(set) var isLoaded: Bool = false

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var cachedPort: Int?
    /// Suppress polling until this date (prevents race between optimistic update and GET)
    private var suppressPollUntil: Date?

    /// Formatted elapsed time since active task started
    var elapsedFormatted: String {
        guard let task = activeTask else { return "" }
        let startDate = Date(timeIntervalSince1970: Double(task.startedAt) / 1000.0)
        let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            // Hours mode: show h:mm only (no seconds clutter)
            return String(format: "%d:%02d", h, m)
        }
        if m > 0 {
            // Minutes mode: show m:ss
            return String(format: "%d:%02d", m, s)
        }
        // Seconds only
        return String(format: "0:%02d", s)
    }

    /// Elapsed time as short label (e.g. "2h 15m" or "Since 09:30")
    var elapsedLabel: String {
        guard let task = activeTask else { return "" }
        let startDate = Date(timeIntervalSince1970: Double(task.startedAt) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "Since \(formatter.string(from: startDate))"
    }

    private init() {
        // Instantly restore the last-known active task from UserDefaults
        // so the UI never flashes the task picker on launch / restart.
        activeTask = Self.loadFromCache()
        if activeTask != nil {
            isLoaded = true
        }
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }

    // MARK: - UserDefaults Cache

    private static func loadFromCache() -> ActiveTaskState? {
        guard let data = UserDefaults.standard.data(forKey: kActiveTaskCacheKey) else { return nil }
        return try? JSONDecoder().decode(ActiveTaskState.self, from: data)
    }

    private func saveToCache(_ task: ActiveTaskState?) {
        if let task = task,
           let data = try? JSONEncoder().encode(task) {
            UserDefaults.standard.set(data, forKey: kActiveTaskCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: kActiveTaskCacheKey)
        }
    }

    // MARK: - Hub Port Discovery

    private func discoverHubPort() async -> Int? {
        if let port = cachedPort, await probePort(port) { return port }
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
        // Tick timer for smooth elapsed display
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeTask != nil else { return }
                self.objectWillChange.send()
            }
        }
    }

    func refresh() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.fetchActiveTask()
        }
    }

    private func fetchActiveTask() async {
        // Skip polling if we recently did an optimistic update (prevents race condition)
        if let suppress = suppressPollUntil, Date() < suppress {
            return
        }
        suppressPollUntil = nil

        guard let port = await discoverHubPort() else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/active-task") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            // Double-check suppression after await (another set/clear may have happened)
            if let suppress = suppressPollUntil, Date() < suppress {
                return
            }

            // Response can be null (no active task) or a JSON object
            if let jsonString = String(data: data, encoding: .utf8),
               jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                self.activeTask = nil
                saveToCache(nil)
            } else {
                let decoded = try JSONDecoder().decode(ActiveTaskState.self, from: data)
                self.activeTask = decoded
                saveToCache(decoded)
            }
            self.isLoaded = true
        } catch {
            // Silent — keep showing the cached value
        }
    }

    // MARK: - Actions

    func setActiveTask(taskId: String, taskName: String, taskColor: String? = nil, source: String = "hub") {
        // Suppress polling for 10s so the optimistic update isn't overwritten by a stale GET
        suppressPollUntil = Date().addingTimeInterval(10)

        // Optimistic update
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let task = ActiveTaskState(
            taskId: taskId,
            taskName: taskName,
            taskColor: taskColor,
            source: source,
            startedAt: now
        )
        self.activeTask = task
        saveToCache(task)

        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/active-task") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "task_id": taskId,
                "task_name": taskName,
                "task_color": taskColor as Any,
                "source": source
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func clearActiveTask() {
        // Suppress polling for 10s so the optimistic update isn't overwritten by a stale GET
        suppressPollUntil = Date().addingTimeInterval(10)
        self.activeTask = nil
        saveToCache(nil)

        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/active-task") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
