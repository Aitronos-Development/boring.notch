//
//  NotchNotificationToast.swift
//  boringNotch
//
//  Floating notification toast that slides out below the Notch.
//  Transient notifications auto-dismiss after 6s with a progress bar.
//  Sticky notifications persist until explicitly dismissed.
//

import SwiftUI

struct NotchNotificationToast: View {
    let notification: CachedNotification
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false
    @State private var progress: CGFloat = 1.0
    @State private var dismissTimer: Timer?

    private let displayDuration: TimeInterval = 6.0

    private var isSticky: Bool { notification.isSticky }

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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Glowing icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Dismiss X
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
            .background {
                ZStack {
                    // Frosted glass background
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.85))

                    // Subtle gradient border
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.4), accentColor.opacity(0.1), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )

                    // Progress bar at bottom (transient only)
                    if !isSticky {
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(accentColor.opacity(0.5))
                                    .frame(width: geo.size.width * progress, height: 2)
                            }
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }
                    }
                }
            }
            .shadow(color: accentColor.opacity(0.15), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .frame(width: 320)
        .offset(y: isVisible ? 0 : -60)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            // Slide in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                isVisible = true
            }

            // Only auto-dismiss transient notifications
            if !isSticky {
                // Countdown progress bar
                withAnimation(.linear(duration: displayDuration)) {
                    progress = 0
                }
                // Auto-dismiss after duration
                dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onDismiss()
                        }
                    }
                }
            }
        }
        .onDisappear {
            dismissTimer?.invalidate()
        }
    }
}
