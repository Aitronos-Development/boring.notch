//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }

        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    static let keyboardInputNotification = Notification.Name("BoringNotchNeedsKeyboardInput")

    private var isSkyLightEnabled: Bool = false

    /// When true, the window can become key to accept keyboard input (e.g. for message text field).
    var needsKeyboardInput: Bool = false {
        didSet {
            guard needsKeyboardInput != oldValue else { return }
            if needsKeyboardInput {
                makeKey()
            } else {
                resignKey()
            }
        }
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        configureWindow()
        setupObservers()
    }

    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false

        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // Apply initial sharing type setting
        updateSharingType()
    }

    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)

        // Listen for keyboard input requests from SwiftUI views (e.g. message text field)
        NotificationCenter.default.publisher(for: Self.keyboardInputNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let enabled = (notification.userInfo?["enabled"] as? Bool) ?? false
                self?.needsKeyboardInput = enabled
            }
            .store(in: &observers)
    }

    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }

    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }

    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }

    private var observers: Set<AnyCancellable> = []

    override var canBecomeKey: Bool { needsKeyboardInput }
    override var canBecomeMain: Bool { false }
}
