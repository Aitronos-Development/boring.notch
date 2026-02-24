//
//  NotchTimelineView.swift
//  boringNotch
//
//  Full-tab time tracking timeline view for the expanded notch.
//  Shows today's time slots as a horizontal timeline bar with status colors.
//  Active task card with live counter when a ticket is running.
//

import Defaults
import SwiftUI

// MARK: - Slot Data Model

struct NotchTimeSlot: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let durationSeconds: UInt64
    let status: String
    let apps: [String]
    let suggestedTaskName: String?
    let isMeeting: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case status
        case apps
        case suggestedTaskName = "suggested_task_name"
        case isMeeting = "is_meeting"
    }
}

// MARK: - Slot Manager

@MainActor
final class NotchTimeSlotManager: ObservableObject {
    static let shared = NotchTimeSlotManager()

    @Published private(set) var slots: [NotchTimeSlot] = []
    @Published private(set) var isLoaded: Bool = false

    private var pollTimer: Timer?
    private var cachedPort: Int?

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func startPolling() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.fetchSlots()
        }
    }

    private func fetchSlots() async {
        guard let port = await discoverPort() else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/slots") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode([NotchTimeSlot].self, from: data)
            self.slots = decoded
            self.isLoaded = true
        } catch {
            // Silent
        }
    }

    private func discoverPort() async -> Int? {
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
}

// MARK: - Timeline View

struct NotchTimelineView: View {
    @ObservedObject var slotManager = NotchTimeSlotManager.shared
    @ObservedObject var timerManager = TimeTrackingManager.shared
    @ObservedObject var summaryManager = TimeSlotSummaryManager.shared
    @ObservedObject var activeTaskManager = ActiveTaskManager.shared

    @State private var hoveredSlotId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Active task card or task picker
            activeTaskSection
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 6)

            // Horizontal timeline bar + stats
            if !slotManager.slots.isEmpty {
                timelineBar
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                statsRow
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            } else {
                emptyView
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Active Task Section

    @ViewBuilder
    private var activeTaskSection: some View {
        if let task = activeTaskManager.activeTask {
            activeTaskCard(task: task)
        } else if activeTaskManager.isLoaded {
            // Only show the task picker once we've confirmed there's genuinely
            // no active task — not while still waiting for the first poll.
            taskPicker
        }
        // else: still loading — show nothing (avoids flash of task picker on startup)
    }

    // MARK: - Active Task Card (with live counter + stats)

    private func activeTaskCard(task: ActiveTaskState) -> some View {
        VStack(spacing: 0) {
            // Main card
            HStack(spacing: 12) {
                // Left: pulsing green dot + task info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green.opacity(0.5), radius: 4)
                        Text(task.taskName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // Live counter — big monospaced
                    Text(activeTaskManager.elapsedFormatted)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())

                    // Started at label
                    Text(activeTaskManager.elapsedLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                // Right: today's mini stats
                VStack(alignment: .trailing, spacing: 6) {
                    // Sessions today
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(summaryManager.totalCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("sessions")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    // Logged time
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(summaryManager.loggedFormatted)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                        Text("logged")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                // Stop button
                VStack(spacing: 4) {
                    Button {
                        activeTaskManager.clearActiveTask()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("Stop")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Bottom action bar
            HStack(spacing: 8) {
                Button {
                    openHubTimeTracking()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 8))
                        Text("Change task")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Spacer()

                if summaryManager.pendingCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                        Text("\(summaryManager.pendingCount) pending")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }

                Button {
                    openHubTimeTracking()
                } label: {
                    HStack(spacing: 3) {
                        Text("Hub")
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
        }
        .background(Color.green.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.green.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Task Picker

    private var taskPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "target")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.7))
                Text("What are you working on?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    openHubTimeTracking()
                } label: {
                    HStack(spacing: 3) {
                        Text("Browse in Hub")
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }

            if timerManager.recentTasks.isEmpty {
                HStack {
                    Text("No recent tasks found")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                ForEach(timerManager.recentTasks, id: \.id) { task in
                    Button {
                        activeTaskManager.setActiveTask(
                            taskId: task.id,
                            taskName: task.name
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(task.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("Start")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green.opacity(0.7))
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.green.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Horizontal Timeline Bar

    private var timelineBar: some View {
        VStack(spacing: 4) {
            // Time labels
            HStack {
                if let first = slotManager.slots.first {
                    Text(formatTime(first.startTime))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                if let last = slotManager.slots.last {
                    Text(formatTime(last.endTime))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // The bar
            GeometryReader { geo in
                let totalDuration = slotManager.slots.reduce(UInt64(0)) { $0 + max($1.durationSeconds, 30) }
                let barWidth = geo.size.width

                HStack(spacing: 1) {
                    ForEach(slotManager.slots) { slot in
                        let slotDuration = max(slot.durationSeconds, 30)
                        let fraction = totalDuration > 0 ? CGFloat(slotDuration) / CGFloat(totalDuration) : 0
                        let segmentWidth = max(fraction * barWidth - 1, 2)

                        slotSegment(slot: slot, width: segmentWidth)
                    }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .green, label: "Logged")
                legendItem(color: .orange, label: "Pending")
                legendItem(color: .blue, label: "Free")
                legendItem(color: .purple, label: "Meeting")
                Spacer()
            }
        }
    }

    private func slotSegment(slot: NotchTimeSlot, width: CGFloat) -> some View {
        let color = slotColor(for: slot)
        let isHovered = hoveredSlotId == slot.id

        return Rectangle()
            .fill(color.opacity(isHovered ? 0.9 : 0.6))
            .frame(width: width, height: 28)
            .overlay(alignment: .center) {
                if slot.isMeeting {
                    Image(systemName: "video.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .onHover { hovering in
                hoveredSlotId = hovering ? slot.id : nil
            }
            .overlay(alignment: .bottom) {
                if isHovered {
                    Text("\(formatTime(slot.startTime))\u{2013}\(formatTime(slot.endTime))")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .offset(y: 16)
                        .zIndex(10)
                }
            }
            .onTapGesture {
                openHubTimeTracking()
            }
    }

    private func slotColor(for slot: NotchTimeSlot) -> Color {
        if slot.isMeeting { return .purple }
        switch slot.status {
        case "Logged": return .green
        case "Pending": return .orange
        case "Skipped": return .gray
        case "FreeTime": return .blue
        default: return .gray
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color.opacity(0.6))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 8) {
            if summaryManager.totalCount > 0 {
                HStack(spacing: 3) {
                    Text("\(summaryManager.loggedCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("logged")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                }

                if summaryManager.pendingCount > 0 {
                    HStack(spacing: 3) {
                        Text("\(summaryManager.pendingCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("pending")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            Button {
                openHubTimeTracking()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                    Text("Open in Hub")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 20))
                .foregroundStyle(.gray.opacity(0.3))
            Text("No time data for today")
                .font(.system(size: 11))
                .foregroundStyle(.gray.opacity(0.5))
            Button {
                openHubTimeTracking()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                    Text("Open Time Tracking")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func formatTime(_ time: String) -> String {
        let parts = time.split(separator: ":")
        if parts.count >= 2 {
            return "\(parts[0]):\(parts[1])"
        }
        return time
    }

    private func openHubTimeTracking() {
        Task {
            guard let port = await TimeSlotSummaryManager.shared.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/navigate") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["path": "/time-tracking"])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Calculate the ideal total notch frame height based on current state.
    /// This must include overhead for BoringHeader (~40pt) and bottom padding (12pt)
    /// since the value is used as maxHeight for the entire notch frame.
    static func idealHeight(
        hasActiveTask: Bool,
        hasSlots: Bool,
        recentTaskCount: Int
    ) -> CGFloat {
        // Frame overhead: BoringHeader (~40pt) + mainLayout bottom padding (12pt)
        var h: CGFloat = 52

        // Content padding (top 6 + bottom 6)
        h += 12

        if hasActiveTask {
            // Active task card: ~110 (card) + action bar
            h += 130
        } else if ActiveTaskManager.shared.isLoaded {
            // Task picker header
            h += 24
            // Task rows (each ~28pt) or empty label
            let taskRows = max(recentTaskCount, 1)
            h += CGFloat(taskRows) * 28
        }
        // else: still loading, no task section rendered

        if hasSlots {
            // Timeline bar: time labels + bar + legend + stats row
            h += 28 + 4 + 12 + 28 + 10 // ~82
        } else {
            // Empty state
            h += 70
        }

        return min(h, 450)
    }
}
