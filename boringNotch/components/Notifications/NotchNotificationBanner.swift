//
//  NotchNotificationBanner.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//

import SwiftUI

/// Persistent notification banner displayed in the notch chin area.
/// Unlike sneak peek (auto-dismiss), this persists until the user clicks Open or Dismiss.
struct NotchNotificationBanner: View {
    let notification: CachedNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var bgColor: Color {
        notification.isUrgent ? Color.red : Color.blue
    }

    private var iconName: String {
        switch notification.notificationType {
        case "announcement": return "megaphone.fill"
        case "request_assigned": return "clipboard.fill"
        case "request_updated": return "arrow.triangle.2.circlepath"
        default: return "bell.badge.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(bgColor)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(notification.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Sender
            if !notification.senderName.isEmpty {
                Text(notification.senderName)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            // Open button
            Button(action: onOpen) {
                Text("Open")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bgColor.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(bgColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
