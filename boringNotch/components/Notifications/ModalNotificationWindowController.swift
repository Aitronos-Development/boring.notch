//
//  ModalNotificationWindowController.swift
//  boringNotch
//
//  Large centered presentation window for important announcements.
//  Distinct from the compact toast — this is an immersive full-content modal
//  that sits in the middle of the notch screen with a dim backdrop behind it.
//
//  Triggered when a notification has `modal: true`.
//

import AppKit
import SwiftUI
import WebKit

// MARK: - Modal Content View

struct ModalNotificationContent: View {
    let notification: CachedNotification
    let onDismiss: () -> Void
    let onOpenInHub: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()
                .background(Color.white.opacity(0.12))

            bodyArea

            Divider()
                .background(Color.white.opacity(0.12))

            actionRow
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.5),
                                    accentColor.opacity(0.15),
                                    .white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
        .shadow(color: accentColor.opacity(0.2), radius: 20, y: 4)
        .scaleEffect(appeared ? 1 : 0.90)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }

    // MARK: - Accent & Icon

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

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if !notification.senderName.isEmpty && notification.senderName != "System" {
                        Text(notification.senderName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text(formattedDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.35))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyArea: some View {
        if !notification.body.isEmpty {
            if notification.isHTML {
                ModalHTMLBodyView(html: notification.body)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(minHeight: 120, maxHeight: 380)
            } else {
                ScrollView {
                    Text(notification.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(minHeight: 80, maxHeight: 300)
            }
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            Button(action: onOpenInHub) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text("Open in Hub")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(accentColor.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Formatted Date

    private var formattedDate: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: notification.createdAt) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: notification.createdAt) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return notification.createdAt
    }
}

// MARK: - Modal HTML Body View

/// A larger WKWebView for the modal — same styling as HTMLBodyView but with
/// a bigger font and scroll support for long content.
struct ModalHTMLBodyView: NSViewRepresentable {
    let html: String

    private static let css = """
        * { box-sizing: border-box; }
        html, body {
            margin: 0; padding: 0;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
            font-size: 14.5px;
            color: rgba(255,255,255,0.88);
            line-height: 1.65;
            letter-spacing: -0.01em;
            -webkit-font-smoothing: antialiased;
            -webkit-text-size-adjust: 100%;
            overflow-x: hidden;
        }
        body { padding: 2px 0; }
        p { margin: 0 0 12px 0; }
        p:last-child { margin-bottom: 0; }
        strong, b {
            color: rgba(255,255,255,1);
            font-weight: 600;
        }
        em, i { color: rgba(255,255,255,0.6); }
        ul, ol {
            margin: 8px 0 14px 0;
            padding-left: 22px;
        }
        li {
            margin: 5px 0;
            padding-left: 4px;
        }
        li::marker { color: rgba(255,255,255,0.4); }
        a {
            color: #60a5fa;
            text-decoration: none;
            border-bottom: 1px solid rgba(96,165,250,0.25);
            transition: border-color 0.15s;
        }
        a:hover {
            border-bottom-color: rgba(96,165,250,0.6);
        }
        h1 { font-size: 20px; font-weight: 700; color: white; margin: 0 0 12px 0; }
        h2 { font-size: 17px; font-weight: 600; color: white; margin: 0 0 10px 0; }
        h3 { font-size: 15px; font-weight: 600; color: rgba(255,255,255,0.95); margin: 0 0 8px 0; }
        hr {
            border: none;
            border-top: 1px solid rgba(255,255,255,0.1);
            margin: 16px 0;
        }
        code {
            font-family: 'SF Mono', 'Menlo', monospace;
            font-size: 0.9em;
            background: rgba(255,255,255,0.08);
            padding: 1px 5px;
            border-radius: 4px;
            color: rgba(255,255,255,0.9);
        }
        blockquote {
            margin: 8px 0 14px 0;
            padding: 8px 14px;
            border-left: 3px solid rgba(96,165,250,0.4);
            background: rgba(255,255,255,0.03);
            border-radius: 0 6px 6px 0;
            color: rgba(255,255,255,0.75);
        }
        blockquote p { margin-bottom: 4px; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb {
            background: rgba(255,255,255,0.15);
            border-radius: 3px;
        }
        ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
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

// MARK: - Modal Window Controller

@MainActor
final class ModalNotificationWindowController {
    static let shared = ModalNotificationWindowController()

    private var modalWindow: NSPanel?
    private var backdropWindow: NSWindow?

    private let modalWidth: CGFloat = 680
    private let modalHeight: CGFloat = 540

    private init() {}

    // MARK: - Screen Detection (same logic as toast)

    private var notchScreen: NSScreen? {
        if let physicalNotch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return physicalNotch
        }
        let uuid = BoringViewCoordinator.shared.selectedScreenUUID
        return NSScreen.screen(withUUID: uuid) ?? NSScreen.main
    }

    // MARK: - Show

    func show(_ notification: CachedNotification) {
        NSLog("[Modal] show() called for: %@", notification.title)
        dismissImmediate()

        guard let screen = notchScreen else {
            NSLog("[Modal] No notchScreen found — aborting")
            return
        }

        NSLog("[Modal] Screen: %@ frame=%@", screen.localizedName, String(describing: screen.frame))
        showBackdrop(on: screen)

        let x = screen.frame.midX - modalWidth / 2
        let y = screen.frame.midY - modalHeight / 2
        let frame = NSRect(x: x, y: y, width: modalWidth, height: modalHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .mainMenu + 6
        panel.hasShadow = false   // SwiftUI shadow handles it
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let hostingView = NSHostingView(
            rootView: ModalNotificationContent(
                notification: notification,
                onDismiss: { [weak self] in
                    self?.dismiss()
                    NotificationManager.shared.dismiss(notification.id)
                },
                onOpenInHub: { [weak self] in
                    self?.dismiss()
                    NotificationManager.shared.openNotification(notification.id)
                }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: CGSize(width: modalWidth, height: modalHeight))
        panel.contentView = hostingView

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.modalWindow = panel

        if notification.hasEffect {
            EffectWindowController.shared.showEffect(notification.effect)
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        let capturedModal = modalWindow
        let capturedBackdrop = backdropWindow
        modalWindow = nil
        backdropWindow = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            capturedModal?.animator().alphaValue = 0
            capturedBackdrop?.animator().alphaValue = 0
        }, completionHandler: {
            capturedModal?.orderOut(nil)
            capturedModal?.close()
            capturedBackdrop?.orderOut(nil)
            capturedBackdrop?.close()
        })
    }

    // MARK: - Backdrop

    private func showBackdrop(on screen: NSScreen) {
        let backdrop = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backdrop.isOpaque = false
        backdrop.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        backdrop.level = .mainMenu + 4 // backdrop +4, effects +5, modal +6
        backdrop.ignoresMouseEvents = true
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backdrop.alphaValue = 0
        backdrop.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            backdrop.animator().alphaValue = 1
        }
        self.backdropWindow = backdrop
    }

    // MARK: - Internal

    private func dismissImmediate() {
        modalWindow?.orderOut(nil)
        modalWindow?.close()
        modalWindow = nil
        backdropWindow?.orderOut(nil)
        backdropWindow?.close()
        backdropWindow = nil
    }
}
