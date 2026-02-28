//
//  TimeTrackingManager.swift
//  boringNotch
//
//  Polls the Hub HTTP API for active timer state and publishes it for the notch UI.
//  Supports starting/stopping timers and fetching recent tasks for the task picker.
//

import Foundation

// MARK: - Data Models

struct TimerStatus: Codable {
    let active: Bool
    let taskId: String?
    let taskName: String?
    let startedAt: Int64?
    let elapsedSeconds: UInt64

    enum CodingKeys: String, CodingKey {
        case active
        case taskId = "task_id"
        case taskName = "task_name"
        case startedAt = "started_at"
        case elapsedSeconds = "elapsed_seconds"
    }
}

struct NotchRecentTask: Codable, Identifiable {
    let id: String
    let name: String
}

// MARK: - Manager

@MainActor
final class TimeTrackingManager: ObservableObject {
    static let shared = TimeTrackingManager()

    @Published private(set) var isTracking: Bool = false
    @Published private(set) var taskName: String = ""
    @Published private(set) var taskId: String = ""
    @Published private(set) var startedAt: Date?
    @Published private(set) var elapsedSeconds: UInt64 = 0
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var recentTasks: [NotchRecentTask] = []

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var taskPollTimer: Timer?
    private var cachedPort: Int?
    private var currentTask: Task<Void, Never>?

    /// Formatted elapsed time: "0:42:15" or "12:30"
    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
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

    private init() {
        startPolling()
        fetchRecentTasks()
        // Refresh recent tasks every 60s
        taskPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchRecentTasks()
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        taskPollTimer?.invalidate()
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
            await self.fetchTimerStatus()
        }
    }

    private func fetchTimerStatus() async {
        guard let port = await discoverHubPort() else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/timer/status") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            let status = try decoder.decode(TimerStatus.self, from: data)

            guard !Task.isCancelled else { return }

            let wasTracking = self.isTracking
            self.isTracking = status.active
            self.taskName = status.taskName ?? ""
            self.taskId = status.taskId ?? ""
            self.elapsedSeconds = status.elapsedSeconds
            self.isLoaded = true

            if let startedMs = status.startedAt {
                self.startedAt = Date(timeIntervalSince1970: Double(startedMs) / 1000.0)
            } else {
                self.startedAt = nil
            }

            // Start/stop tick timer based on tracking state
            if status.active && !wasTracking {
                startTickTimer()
            } else if !status.active && wasTracking {
                stopTickTimer()
            }
        } catch {
            // Silently ignore — Hub may not be running
        }
    }

    // MARK: - Tick Timer (local 1s updates for smooth elapsed display)

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isTracking else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Actions

    func startTimer(taskId: String, taskName: String) {
        // Optimistic update
        self.isTracking = true
        self.taskId = taskId
        self.taskName = taskName
        self.elapsedSeconds = 0
        self.startedAt = Date()
        startTickTimer()

        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/timer/start") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = ["task_id": taskId, "task_name": taskName]
            request.httpBody = try? JSONEncoder().encode(body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func stopTimer() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/timer/stop") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)

            // Optimistic update
            self.isTracking = false
            self.taskName = ""
            self.taskId = ""
            self.elapsedSeconds = 0
            self.startedAt = nil
            self.stopTickTimer()
        }
    }

    // MARK: - Recent Tasks

    private func fetchRecentTasks() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let port = await self.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/tasks/recent") else { return }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { return }

                let tasks = try JSONDecoder().decode([NotchRecentTask].self, from: data)
                guard !Task.isCancelled else { return }
                self.recentTasks = tasks
            } catch {
                // Silently ignore
            }
        }
    }
}
