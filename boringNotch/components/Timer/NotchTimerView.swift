//
//  NotchTimerView.swift
//  boringNotch
//
//  Expanded timer panel shown in the notch when a task timer is active.
//  Supports starting timers from recent tasks and stopping active timers.
//

import Defaults
import SwiftUI

struct NotchTimerView: View {
    @ObservedObject var timerManager = TimeTrackingManager.shared
    @ObservedObject var activeTaskManager = ActiveTaskManager.shared
    @ObservedObject var slotManager = TimeSlotSummaryManager.shared
    @Default(.notchExpandedLayout) private var expandedLayout

    private var isCompact: Bool {
        expandedLayout == .stacked
    }

    var body: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            if timerManager.isTracking {
                activeTimerView
            } else if activeTaskManager.activeTask != nil {
                activeTaskView
            } else {
                idleTimerView
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Active Timer (manual ClickUp timer)

    private var activeTimerView: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            // Tracking badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
                Text("Tracking")
                    .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())

            // Task name
            Text(timerManager.taskName)
                .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)

            // Large elapsed time
            Text(timerManager.elapsedFormatted)
                .font(.system(size: isCompact ? 20 : 30, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            // Stop button
            Button {
                timerManager.stopTimer()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: isCompact ? 8 : 10))
                    Text("Stop")
                        .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, isCompact ? 8 : 12)
                .padding(.vertical, isCompact ? 4 : 6)
                .background(Color.red.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())

            slotSummaryFooter
        }
    }

    // MARK: - Active Task (auto-logging mode)

    private var activeTaskView: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            if let task = activeTaskManager.activeTask {
                // Auto-logging badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Auto-logging")
                        .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())

                // Task name
                Text(task.taskName)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)

                // Elapsed time — the main focus
                Text(activeTaskManager.elapsedFormatted)
                    .font(.system(size: isCompact ? 20 : 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)

                // Stop button
                Button {
                    activeTaskManager.clearActiveTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: isCompact ? 8 : 10))
                        Text("Stop")
                            .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, isCompact ? 8 : 12)
                    .padding(.vertical, isCompact ? 4 : 6)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PlainButtonStyle())

                slotSummaryFooter
            }
        }
    }

    // MARK: - Idle (no timer) — show recent tasks to start

    private var idleTimerView: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            if timerManager.recentTasks.isEmpty {
                // No recent tasks — prompt to open Hub
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: isCompact ? 14 : 20))
                        .foregroundStyle(.gray.opacity(0.5))
                    Text("No recent tasks")
                        .font(.system(size: isCompact ? 9 : 11))
                        .foregroundStyle(.gray.opacity(0.5))
                    Button {
                        openHubTimeTracking()
                    } label: {
                        Text("Open Time Tracking")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Start Timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Recent task buttons (max 3 to fit, 2 if compact)
                ForEach(timerManager.recentTasks.prefix(isCompact ? 2 : 3), id: \.id) { task in
                    Button {
                        timerManager.startTimer(taskId: task.id, taskName: task.name)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text(task.name)
                                .font(.system(size: isCompact ? 10 : 11))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.green.opacity(0.6))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, isCompact ? 3 : 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Slot summary footer

    @ViewBuilder
    private var slotSummaryFooter: some View {
        if slotManager.totalCount > 0 {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.top, 2)

            if slotManager.hasPendingSlots {
                // Pending slots exist — show warning row
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(slotManager.pendingCount) unlogged · \(slotManager.pendingFormatted)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange.opacity(0.9))
                        Spacer()
                    }
                    if slotManager.loggedCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(.green.opacity(0.6))
                            Text("\(slotManager.loggedCount) logged · \(slotManager.loggedFormatted)")
                                .font(.system(size: 9))
                                .foregroundStyle(.gray)
                            Spacer()
                        }
                    }
                }

            } else {
                // All caught up
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text("\(slotManager.loggedCount) logged · \(slotManager.loggedFormatted)")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                    Spacer()
                }

            }
        }
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
}
