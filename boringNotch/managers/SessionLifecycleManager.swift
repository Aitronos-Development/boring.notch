//
//  SessionLifecycleManager.swift
//  boringNotch
//
//  Central coordinator for time tracking session lifecycle.
//  Observes:
//    - Screen lock/unlock (DistributedNotificationCenter)
//    - New meeting slots (Combine subscription on NotchTimeSlotManager.$slots)
//
//  On lock:   stops the active timer/task so time isn't logged while away
//  On unlock: always shows "What are you working on?" prompt to resume or pick a new task
//  On meeting: shows "Meeting detected" prompt
//

import Combine
import Foundation

@MainActor
final class SessionLifecycleManager {
    static let shared = SessionLifecycleManager()

    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var slotsCancellable: AnyCancellable?
    private var previousMeetingSlotIds: Set<String> = []
    private var isFirstSlotLoad = true
    /// The task that was active when the screen locked — offered as the first option on unlock
    private var taskAtLock: ActiveTaskState? = nil

    private init() {
        setupScreenObservers()
        setupMeetingDetection()
    }

    deinit {
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        slotsCancellable?.cancel()
    }

    // MARK: - Screen Lock/Unlock

    private func setupScreenObservers() {
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onScreenLocked()
            }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onScreenUnlocked()
            }
        }
    }

    private func onScreenLocked() {
        // Remember what was running, then stop it so time isn't logged while away.
        taskAtLock = ActiveTaskManager.shared.activeTask
        if taskAtLock != nil {
            ActiveTaskManager.shared.clearActiveTask()
        }
        if TimeTrackingManager.shared.isTracking {
            TimeTrackingManager.shared.stopTimer()
        }
    }

    private func onScreenUnlocked() {
        // Always show the prompt after unlock — let the user decide what to work on next.
        // Pass the previously-running task so it appears at the top of the list.
        let previousTask = taskAtLock
        taskAtLock = nil

        // Delay to let macOS settle (login animation, window restoration)
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            await MainActor.run {
                TimeTrackingPromptWindowController.shared.show(.welcomeBack, previousTask: previousTask)
            }
        }
    }

    // MARK: - Meeting Detection
    //
    // Disabled: The backend `is_meeting` flag has too many false positives
    // (Slack running in background flags every slot as a meeting).
    // The Rust meeting-app list has been fixed, but until the Hub is rebuilt
    // and the detection is validated, keep the popup suppressed.
    // Re-enable by uncommenting `setupMeetingDetection()` in init().

    private func setupMeetingDetection() {
        // Intentionally no-op — see comment above.
    }

    private func handleSlotsUpdate(_ slots: [NotchTimeSlot]) {
        // No-op while meeting detection is disabled.
    }
}
