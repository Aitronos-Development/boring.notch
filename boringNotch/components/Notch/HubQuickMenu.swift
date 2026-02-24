//
//  HubQuickMenu.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//

import SwiftUI

/// A popover menu listing Hub pages, Fleet Dashboard, and Show/Hide Hub Window.
/// Triggered from the header button in BoringHeader.
struct HubQuickMenu: View {
    @ObservedObject var manager = HubNavigationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header
            Text("Hub Pages")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ForEach(manager.pages) { page in
                Button(action: {
                    manager.navigateToPage(page.path)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .frame(width: 16)
                            .imageScale(.small)
                        Text(page.label)
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HubMenuButtonStyle())
            }

            Divider()
                .padding(.horizontal, 8)

            // Fleet Dashboard
            Button(action: {
                manager.openFleetDashboard()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .frame(width: 16)
                        .imageScale(.small)
                    Text("Fleet Dashboard")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(HubMenuButtonStyle())

            // Show/Hide Hub Window
            Button(action: {
                manager.toggleHubWindow()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .frame(width: 16)
                        .imageScale(.small)
                    Text("Show/Hide Hub")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(HubMenuButtonStyle())
        }
        .padding(.vertical, 4)
        .frame(width: 180)
    }
}

/// Custom button style for menu items — highlights on hover
struct HubMenuButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
            )
            .foregroundColor(isHovered ? .white : .secondary)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
