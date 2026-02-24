//
//  NotificationDetailView.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//

import SwiftUI

/// Expanded notification view shown when the user clicks a notification banner.
/// Displays the full rich text body, sender info, timestamp, and action buttons.
struct NotificationDetailView: View {
    let notification: CachedNotification
    let onDismiss: () -> Void
    let onOpenInHub: () -> Void
    let onClose: () -> Void

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

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: notification.createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: notification.createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return notification.createdAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(bgColor)

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

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Body
            if !notification.body.isEmpty {
                ScrollView {
                    if notification.isHTML {
                        NotificationHTMLView(html: notification.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(notification.body)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxHeight: 120)
            }

            // Effect badge
            if notification.hasEffect {
                HStack(spacing: 4) {
                    Image(systemName: effectIconName(notification.effect))
                        .font(.system(size: 9))
                    Text(notification.effect.capitalized)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(bgColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(bgColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Divider
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
                    .background(bgColor.opacity(0.6))
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

                if notification.isUrgent {
                    Text("Urgent")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(bgColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(
            .scale(scale: 0.92, anchor: .top)
            .combined(with: .opacity)
        )
    }

    private func effectIconName(_ effect: String) -> String {
        switch effect {
        case "confetti": return "party.popper.fill"
        case "hearts": return "heart.fill"
        case "fireworks": return "sparkles"
        case "spotlight": return "sun.max.fill"
        case "celebration": return "trophy.fill"
        default: return "wand.and.stars"
        }
    }
}
