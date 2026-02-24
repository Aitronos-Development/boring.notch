//
//  NotchTimeTrackingView.swift
//  boringNotch
//
//  Shows time tracking slot summary in the notch when pending slots exist.
//  Replaces the calendar view until all slots are resolved.
//  Clicking anywhere opens the Hub Time Tracking page.
//

import Defaults
import SwiftUI

struct NotchTimeTrackingView: View {
    @ObservedObject var slotManager = TimeSlotSummaryManager.shared
    @Default(.notchExpandedLayout) private var expandedLayout

    private var isCompact: Bool {
        expandedLayout == .stacked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
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
        .onTapGesture {
            openHubTimeTracking()
        }
    }

    // MARK: - Pending Slots

    private var pendingView: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Time Tracking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                // "Open" chevron hint
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Stats
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(slotManager.pendingCount)")
                        .font(.system(size: isCompact ? 16 : 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("pending")
                        .font(.system(size: isCompact ? 9 : 10))
                        .foregroundStyle(.gray)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(slotManager.pendingFormatted)
                        .font(.system(size: isCompact ? 16 : 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("unlogged")
                        .font(.system(size: isCompact ? 9 : 10))
                        .foregroundStyle(.gray)
                }
            }

            // Next pending slot (hide in compact to save space)
            if !isCompact, let next = slotManager.nextPendingSlot {
                Divider()
                    .background(Color.white.opacity(0.1))

                HStack(spacing: 6) {
                    if next.isMeeting {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple)
                    }

                    Text(formatTimeRange(next.startTime, next.endTime))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))

                    if let taskName = next.suggestedTaskName, !taskName.isEmpty {
                        Text(taskName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !next.apps.isEmpty {
                        Text(next.apps.prefix(2).joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
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

            Text("\(slotManager.loggedCount) logged \u{00B7} \(slotManager.loggedFormatted)")
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty (no slots yet)

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: isCompact ? 14 : 18))
                .foregroundStyle(.gray.opacity(0.4))
            Text("No time data")
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.gray.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatTimeRange(_ start: String, _ end: String) -> String {
        let startShort = formatTime(start)
        let endShort = formatTime(end)
        return "\(startShort)\u{2013}\(endShort)"
    }

    private func formatTime(_ time: String) -> String {
        // "HH:MM:SS" → "HH:MM"
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
}
