//
//  TimeTrackingPromptWindowController.swift
//  boringNotch
//
//  Floating prompt window for time tracking lifecycle events.
//  Two modes:
//    1. Welcome Back — shown after screen unlock, asks "What are you working on?"
//    2. Meeting Detected — shown when a new meeting slot appears, asks to reassign
//
//  Follows the same NSPanel pattern as NotificationToastWindowController.
//

import AppKit
import SwiftUI

// MARK: - Prompt Type

enum TimeTrackingPromptType {
    case welcomeBack
    case meetingDetected(appName: String, startTime: String, endTime: String)
}

// MARK: - Prompt Content View

struct TimeTrackingPromptContent: View {
    let promptType: TimeTrackingPromptType
    let recentTasks: [NotchRecentTask]
    let previousTask: ActiveTaskState?
    let onSelectTask: (NotchRecentTask) -> Void
    let onOpenHub: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Task list — previous task pinned at top, then recent tasks
            if recentTasks.isEmpty && previousTask == nil {
                emptyTasksView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    // Previous task (pinned, highlighted)
                    if let prev = previousTask {
                        previousTaskRow(prev)
                    }
                    // Recent tasks (skip any that duplicate the previous task)
                    let filtered = recentTasks.filter { $0.id != previousTask?.taskId }
                    ForEach(filtered.prefix(previousTask != nil ? 2 : 3), id: \.id) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Actions
            actionsView
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.4), accentColor.opacity(0.1), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        }
        .shadow(color: accentColor.opacity(0.12), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private var accentColor: Color {
        switch promptType {
        case .welcomeBack: return .blue
        case .meetingDetected: return .purple
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        switch promptType {
        case .welcomeBack:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Welcome back!")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("What are you working on now?")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

        case .meetingDetected(let appName, let startTime, let endTime):
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text("Meeting detected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text(appName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(formatTime(startTime))–\(formatTime(endTime))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("What ticket should this be logged on?")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Previous Task Row (pinned, highlighted)

    private func previousTaskRow(_ task: ActiveTaskState) -> some View {
        Button {
            onSelectTask(NotchRecentTask(id: task.taskId, name: task.taskName))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)

                Text(task.taskName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text("Resume")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.green.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Row

    private func taskRow(_ task: NotchRecentTask) -> some View {
        Button {
            onSelectTask(task)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: 6, height: 6)

                Text(task.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty Tasks

    private var emptyTasksView: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
            Text("No recent tasks")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsView: some View {
        HStack(spacing: 8) {
            Button(action: onOpenHub) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                    Text("Open Hub")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            switch promptType {
            case .meetingDetected:
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9))
                        Text("Keep current")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

            case .welcomeBack:
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                        Text("Dismiss")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: String) -> String {
        let parts = time.split(separator: ":")
        if parts.count >= 2 {
            return "\(parts[0]):\(parts[1])"
        }
        return time
    }
}

// MARK: - Window Controller

@MainActor
final class TimeTrackingPromptWindowController {
    static let shared = TimeTrackingPromptWindowController()

    private var promptWindow: NSPanel?
    private var dismissTimer: Timer?

    private let promptWidth: CGFloat = 340

    private init() {}

    /// Find the screen where the Notch is displayed.
    private var notchScreen: NSScreen? {
        let uuid = BoringViewCoordinator.shared.selectedScreenUUID
        return NSScreen.screen(withUUID: uuid) ?? NSScreen.main
    }

    /// Show a time tracking prompt below the notch.
    func show(_ promptType: TimeTrackingPromptType, previousTask: ActiveTaskState? = nil) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Dismiss any existing prompt first
        dismissImmediate()

        guard let screen = notchScreen else { return }

        let recentTasks = TimeTrackingManager.shared.recentTasks

        let frame = promptFrame(on: screen)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .mainMenu + 3
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        let hostingView = NSHostingView(
            rootView: TimeTrackingPromptContent(
                promptType: promptType,
                recentTasks: recentTasks,
                previousTask: previousTask,
                onSelectTask: { [weak self] task in
                    ActiveTaskManager.shared.setActiveTask(
                        taskId: task.id,
                        taskName: task.name
                    )
                    self?.dismiss()
                },
                onOpenHub: { [weak self] in
                    self?.dismiss()
                    self?.openHubTimeTracking()
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
            .frame(width: promptWidth)
        )
        panel.contentView = hostingView

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.promptWindow = panel

        // Auto-dismiss after 30s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    /// Dismiss with fade-out animation.
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let window = promptWindow else { return }
        let captured = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            captured.animator().alphaValue = 0
        }, completionHandler: {
            captured.orderOut(nil)
            captured.close()
        })
        promptWindow = nil
    }

    /// Dismiss immediately (no animation).
    private func dismissImmediate() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let window = promptWindow {
            window.orderOut(nil)
            window.close()
        }
        promptWindow = nil
    }

    // MARK: - Private Helpers

    private func promptFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let notchHeight: CGFloat = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : (screen.frame.maxY - screen.visibleFrame.maxY)
        // Estimate height — the hosting view will intrinsically size, but we need an initial frame
        let height: CGFloat = 220
        let gap: CGFloat = 6

        let x = screenFrame.origin.x + (screenFrame.width - promptWidth) / 2
        let y = screenFrame.origin.y + screenFrame.height - notchHeight - height - gap

        return NSRect(x: x, y: y, width: promptWidth, height: height)
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
