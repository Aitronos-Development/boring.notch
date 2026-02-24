//
//  NotificationToastWindowController.swift
//  boringNotch
//
//  Manages a separate floating window for notification toasts.
//  The toast appears below the physical notch as an independent overlay,
//  completely decoupled from the Notch's open/close state.
//
//  Two modes:
//    1. Toast (compact) — brief preview, auto-dismisses for transient
//    2. Detail (expanded) — full notification with action buttons
//

import AppKit
import SwiftUI
import WebKit

// MARK: - Toast Content View (manages both modes)

struct NotificationToastContent: View {
    let notification: CachedNotification
    let isExpanded: Bool
    let onTap: () -> Void
    let onDismiss: () -> Void
    let onOpenInHub: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.9))
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
        .shadow(color: accentColor.opacity(0.15), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private var accentColor: Color {
        switch notification.notificationType {
        case "announcement": return .blue
        case "request_assigned": return .orange
        case "request_updated": return .cyan
        case "system": return .purple
        default: return .blue
        }
    }

    private var iconName: String {
        switch notification.notificationType {
        case "announcement": return "megaphone.fill"
        case "request_assigned": return "clipboard.fill"
        case "request_updated": return "arrow.triangle.2.circlepath"
        case "system": return "bell.badge.fill"
        default: return "bell.badge.fill"
        }
    }

    /// Plain-text body preview — strips HTML tags so raw markup never appears in the compact toast.
    private var bodyPreview: String {
        guard !notification.body.isEmpty else { return "" }
        guard notification.isHTML else { return notification.body }
        return notification.body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Compact Toast

    @ViewBuilder
    private var compactView: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    let preview = bodyPreview
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 16, height: 16)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if !notification.senderName.isEmpty {
                            Text(notification.senderName)
                                .font(.system(size: 10))
                                .foregroundStyle(.gray)
                        }
                        Text(formattedDate)
                            .font(.system(size: 10))
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Body — HTML or plain text
            if !notification.body.isEmpty {
                if notification.isHTML {
                    HTMLBodyView(html: notification.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxHeight: 160)
                } else {
                    ScrollView {
                        Text(notification.body)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxHeight: 100)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Actions
            HStack(spacing: 8) {
                Button(action: onOpenInHub) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Open in Hub")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
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

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: notification.createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: notification.createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return notification.createdAt
    }
}

// MARK: - HTML Body Renderer

/// Renders HTML notification body inside a transparent WKWebView.
/// Styled to match the toast's dark theme with matching typography.
struct HTMLBodyView: NSViewRepresentable {
    let html: String

    private static let css = """
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 11px;
            color: rgba(255,255,255,0.85);
            background: transparent;
            margin: 0; padding: 0;
            line-height: 1.5;
            -webkit-font-smoothing: antialiased;
        }
        p { margin: 0 0 6px 0; }
        ul { margin: 4px 0 6px 0; padding-left: 16px; }
        li { margin: 2px 0; }
        strong { color: rgba(255,255,255,1); }
        em { color: rgba(255,255,255,0.65); font-style: italic; }
        a { color: #60a5fa; text-decoration: none; }
        a:hover { text-decoration: underline; }
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.enclosingScrollView?.hasVerticalScroller = false
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let page = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>\(Self.css)</style>
        </head>
        <body>\(html)</body>
        </html>
        """
        nsView.loadHTMLString(page, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

// MARK: - Window Controller

@MainActor
final class NotificationToastWindowController: ObservableObject {
    static let shared = NotificationToastWindowController()

    private var toastWindow: NSPanel?
    private var dismissTimer: Timer?
    @Published private(set) var currentNotification: CachedNotification?
    @Published private(set) var isExpanded: Bool = false

    private let toastWidth: CGFloat = 360
    private let toastCompactHeight: CGFloat = 56
    private let toastExpandedHeight: CGFloat = 300

    private init() {}

    /// Find the screen where the physical notch is located (multi-monitor aware).
    /// Prioritises the screen with safeAreaInsets.top > 0 (the MacBook notch screen),
    /// then falls back to the user's configured screen UUID, then NSScreen.main.
    private var notchScreen: NSScreen? {
        if let physicalNotch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return physicalNotch
        }
        let uuid = BoringViewCoordinator.shared.selectedScreenUUID
        return NSScreen.screen(withUUID: uuid) ?? NSScreen.main
    }

    /// Show a notification toast below the notch.
    func show(_ notification: CachedNotification) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        // If already showing the same notification, ignore
        if currentNotification?.id == notification.id { return }

        // Dismiss any existing toast first
        dismissWindowImmediate()

        currentNotification = notification
        isExpanded = false

        guard let screen = notchScreen else { return }

        let frame = toastFrame(on: screen, expanded: false)

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

        updateContent(panel: panel, notification: notification, expanded: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Slide in from top + fade
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.toastWindow = panel

        // Trigger full-screen effect if applicable
        if notification.hasEffect {
            EffectWindowController.shared.showEffect(notification.effect)
        }

        // Auto-dismiss transient notifications
        if !notification.isSticky {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.dismissWindow()
                }
            }
        }
    }

    /// Expand the toast to show full detail.
    func expand() {
        guard let panel = toastWindow, let notification = currentNotification else { return }
        guard !isExpanded else { return }

        dismissTimer?.invalidate()
        dismissTimer = nil
        isExpanded = true

        guard let screen = notchScreen else { return }
        let frame = toastFrame(on: screen, expanded: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }

        updateContent(panel: panel, notification: notification, expanded: true)
    }

    /// Dismiss the toast with fade-out animation.
    func dismissWindow() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let window = toastWindow else { return }
        let captured = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            captured.animator().alphaValue = 0
        }, completionHandler: {
            captured.orderOut(nil)
            captured.close()
        })
        toastWindow = nil
        currentNotification = nil
        isExpanded = false
    }

    /// Dismiss immediately (no animation).
    private func dismissWindowImmediate() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let window = toastWindow {
            window.orderOut(nil)
            window.close()
        }
        toastWindow = nil
        currentNotification = nil
        isExpanded = false
    }

    // MARK: - Private Helpers

    private func toastFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let screenFrame = screen.frame
        let notchHeight: CGFloat = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : (screen.frame.maxY - screen.visibleFrame.maxY)
        let height = expanded ? toastExpandedHeight : toastCompactHeight
        let gap: CGFloat = 6

        let x = screenFrame.origin.x + (screenFrame.width - toastWidth) / 2
        let y = screenFrame.origin.y + screenFrame.height - notchHeight - height - gap

        return NSRect(x: x, y: y, width: toastWidth, height: height)
    }

    private func updateContent(panel: NSPanel, notification: CachedNotification, expanded: Bool) {
        let hostingView = NSHostingView(
            rootView: NotificationToastContent(
                notification: notification,
                isExpanded: expanded,
                onTap: { [weak self] in
                    guard let self = self, let n = self.currentNotification else { return }
                    // If the notification links to a Notch view, navigate there
                    if let notchView = Self.notchViewForLink(n.link) {
                        self.dismissWindow()
                        NotificationManager.shared.dismiss(n.id)
                        BoringViewCoordinator.shared.currentView = notchView
                    } else {
                        self.expand()
                    }
                },
                onDismiss: { [weak self] in
                    guard let self = self, let n = self.currentNotification else { return }
                    self.dismissWindow()
                    NotificationManager.shared.dismiss(n.id)
                },
                onOpenInHub: { [weak self] in
                    guard let self = self, let n = self.currentNotification else { return }
                    self.dismissWindow()
                    NotificationManager.shared.openNotification(n.id)
                }
            )
            .frame(width: toastWidth)
        )
        panel.contentView = hostingView
    }

    /// Map a notification link path to a Notch view, if applicable.
    private static func notchViewForLink(_ link: String) -> NotchViews? {
        switch link {
        case "/vpn": return .vpn
        case "/time-tracking": return .timeTracking
        default: return nil
        }
    }
}
