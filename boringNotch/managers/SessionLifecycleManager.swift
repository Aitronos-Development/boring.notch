//
//  SessionLifecycleManager.swift
//  boringNotch
//
//  Central coordinator for time tracking session lifecycle.
//  Observes:
//    - Screen lock/unlock (DistributedNotificationCenter)
//    - New meeting slots (Combine subscription on NotchTimeSlotManager.$slots)
//
//  On lock:   remembers active task (does NOT clear it)
//  On unlock: silently resumes if a task was running; only prompts if no task was active
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
    /// Whether a task was active when the screen was locked — used to skip the prompt on unlock
    private var hadActiveTaskAtLock = false

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
        // Remember whether a task was active — do NOT clear it.
        // The user shouldn't have to re-select their task every time they lock the screen.
        hadActiveTaskAtLock = ActiveTaskManager.shared.activeTask != nil
    }

    private func onScreenUnlocked() {
        // If a task was already running, just let it continue — no prompt needed.
        // Only show the "Welcome back" prompt if there was no active task.
        if hadActiveTaskAtLock || ActiveTaskManager.shared.activeTask != nil {
            return
        }

        // Delay to let macOS settle (login animation, window restoration)
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            await MainActor.run {
                // Double-check — a task might have been set during the delay
                guard ActiveTaskManager.shared.activeTask == nil else { return }
                TimeTrackingPromptWindowController.shared.show(.welcomeBack)
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
