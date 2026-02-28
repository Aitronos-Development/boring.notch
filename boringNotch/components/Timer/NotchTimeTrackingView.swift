//
//  NotchTimeTrackingView.swift
//  boringNotch
//
//  Persistent time tracking banner shown when there are unlogged sessions.
//  Stays visible until the user acts — cannot be dismissed without logging,
//  marking as free time, or skipping. Quick actions are available inline.
//

import Defaults
import SwiftUI

struct NotchTimeTrackingView: View {
    @ObservedObject var slotManager = TimeSlotSummaryManager.shared
    @ObservedObject var activeTaskManager = ActiveTaskManager.shared
    @ObservedObject var timerManager = TimeTrackingManager.shared
    @Default(.notchExpandedLayout) private var expandedLayout

    /// Which quick-action sheet is expanded inline
    @State private var expanded: ExpandedAction? = nil
    @State private var taskSearchQuery: String = ""
    @State private var searchResults: [NotchRecentTask] = []
    @State private var isSearching: Bool = false

    private var isCompact: Bool { expandedLayout == .stacked }

    enum ExpandedAction { case taskPicker }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if slotManager.hasPendingSlots {
                pendingView
            } else if slotManager.totalCount > 0 {
                allCaughtUpView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Pending (persistent — no tap-to-dismiss)

    private var pendingView: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Time Tracking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    openHubTimeTracking()
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(PlainButtonStyle())
            }

            // ── Stats row ────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Count badge
                Text("\(slotManager.pendingCount)")
                    .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(" pending")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.gray)
                    .baselineOffset(isCompact ? 1 : 2)
                Text("  ·  ")
                    .font(.system(size: isCompact ? 9 : 10))
                    .foregroundStyle(.white.opacity(0.2))
                Text(slotManager.pendingFormatted)
                    .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(" unlogged")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.gray)
                    .baselineOffset(isCompact ? 1 : 2)
            }
            // Session status on its own line — always fits
            sessionStatusPill
                .frame(maxWidth: .infinity, alignment: .leading)

            // ── Inline task picker (expands when tapped) ─────────────
            if expanded == .taskPicker {
                taskPickerExpanded
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Color.white.opacity(0.08))

            // ── Quick action buttons ─────────────────────────────────
            quickActions
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.15), value: expanded)
    }

    // MARK: - Session status pill

    @ViewBuilder
    private var sessionStatusPill: some View {
        if timerManager.isTracking {
            statusPill(icon: "timer", label: timerManager.taskName.isEmpty ? "Tracking" : timerManager.taskName, color: .orange)
        } else if let task = activeTaskManager.activeTask {
            statusPill(icon: "bolt.fill", label: task.taskName, color: .green)
        } else {
            statusPill(icon: "circle.slash", label: "Not logged", color: .red.opacity(0.8))
        }
    }

    private func statusPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Image(systemName: icon).font(.system(size: 7)).foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Task picker (inline expansion)

    private var taskPickerExpanded: some View {
        VStack(spacing: 4) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                TextField("Search tasks…", text: $taskSearchQuery)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.9))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: taskSearchQuery) { query in
                        performSearch(query: query)
                    }
                if !taskSearchQuery.isEmpty {
                    Button {
                        taskSearchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // Task list — search results or recents
            let displayTasks = taskSearchQuery.isEmpty
                ? Array(timerManager.recentTasks.prefix(5))
                : searchResults

            if displayTasks.isEmpty && !isSearching {
                Text(taskSearchQuery.isEmpty ? "No recent tasks" : "No results")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                ForEach(displayTasks, id: \.id) { task in
                    Button {
                        setActiveTask(id: task.id, name: task.name)
                        expanded = nil
                        taskSearchQuery = ""
                        searchResults = []
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green.opacity(0.4)).frame(width: 5, height: 5)
                            Text(task.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 8))
                                .foregroundStyle(.green.opacity(0.6))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            guard let port = await TimeSlotSummaryManager.shared.discoverHubPort() else {
                await MainActor.run { isSearching = false }
                return
            }
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/tasks/search?q=\(encoded)") else {
                await MainActor.run { isSearching = false }
                return
            }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let results = try? JSONDecoder().decode([NotchRecentTask].self, from: data) {
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } else {
                await MainActor.run { isSearching = false }
            }
        }
    }

    // MARK: - Quick action bar

    private var quickActions: some View {
        HStack(spacing: 5) {
            // Log to task
            actionButton(
                icon: "tag.fill",
                label: "Log Task",
                color: .green,
                active: expanded == .taskPicker
            ) {
                withAnimation {
                    if expanded == .taskPicker {
                        expanded = nil
                        taskSearchQuery = ""
                        searchResults = []
                    } else {
                        expanded = .taskPicker
                    }
                }
            }

            // Free time
            actionButton(icon: "leaf.fill", label: "Free Time", color: .blue) {
                markCurrentSlot(status: "FreeTime")
            }

            // Skip / not work
            actionButton(icon: "forward.fill", label: "Skip", color: .gray) {
                markCurrentSlot(status: "Skipped")
            }

            // Mark entire day as free (only when many pending)
            if slotManager.pendingCount > 2 {
                actionButton(icon: "sun.max.fill", label: "Day Off", color: .yellow) {
                    markAllSlots(status: "FreeTime")
                }
            }
        }
        .padding(.top, 2)
    }

    private func actionButton(
        icon: String, label: String, color: Color,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(active ? .white : color)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(active ? .white.opacity(0.9) : color.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(active ? color : color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: isCompact ? 14 : 20))
                .foregroundStyle(.green)
            Text("All Caught Up")
                .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("\(slotManager.loggedCount) logged · \(slotManager.loggedFormatted)")
                .font(.system(size: isCompact ? 8 : 9))
                .foregroundStyle(.gray)
            sessionStatusPill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: isCompact ? 14 : 18))
                .foregroundStyle(.gray.opacity(0.4))
            Text("No time data")
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.gray.opacity(0.4))
            sessionStatusPill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Set an active task — optimistic update first, then persist via Hub HTTP bridge
    private func setActiveTask(id: String, name: String) {
        // Instant optimistic update — no waiting for HTTP
        ActiveTaskManager.shared.setActiveTask(taskId: id, taskName: name, source: "notch")
    }

    /// Mark the next pending slot with a status
    private func markCurrentSlot(status: String) {
        guard let next = slotManager.nextPendingSlot else { return }
        // We mark by next-pending — build a synthetic ID from start time
        let slotId = slotIdFromTime(next.startTime)
        markSlot(id: slotId, status: status)
    }

    /// Mark ALL pending slots (e.g. "Day Off")
    private func markAllSlots(status: String) {
        Task {
            guard let port = await TimeSlotSummaryManager.shared.discoverHubPort() else { return }
            // POST to a batch endpoint or mark one by one
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/slots/all/mark") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["status": status])
            _ = try? await URLSession.shared.data(for: req)
            // Also trigger a summary refresh
            await TimeSlotSummaryManager.shared.refresh()
        }
    }

    private func markSlot(id: String, status: String, taskId: String? = nil, taskName: String? = nil) {
        Task {
            guard let port = await TimeSlotSummaryManager.shared.discoverHubPort() else { return }
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/time-tracking/slots/\(encoded)/mark") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["status": status]
            if let tid = taskId { body["task_id"] = tid }
            if let tname = taskName { body["task_name"] = tname }
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
            // Refresh summary so pending count updates immediately
            await TimeSlotSummaryManager.shared.refresh()
        }
    }

    /// Build a slot ID from the start time string (matches backend convention)
    private func slotIdFromTime(_ startTime: String) -> String {
        // Slots are keyed by date+start in "YYYY-MM-DD_HH:MM" format in the backend
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let hhmm = String(startTime.prefix(5))
        return "\(today)_\(hhmm)"
    }

    private func openHubTimeTracking() {
        Task {
            guard let port = await TimeSlotSummaryManager.shared.discoverHubPort() else { return }
            guard let url = URL(string: "http://127.0.0.1:\(port)/hub/window/navigate") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(["path": "/time-tracking"])
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
