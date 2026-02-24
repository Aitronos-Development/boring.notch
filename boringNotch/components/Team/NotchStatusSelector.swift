//
//  NotchStatusSelector.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-17.
//

import SwiftUI

@MainActor
struct NotchStatusSelector: View {
    @ObservedObject var teamManager = TeamPresenceManager.shared
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(colorForStatus(teamManager.currentUserStatus))
                    .frame(width: 6, height: 6)

                Text(teamManager.currentUserStatus.label)
                    .font(.caption2)
                    .foregroundStyle(.gray)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PresenceStatus.allCases, id: \.self) { status in
                    Button {
                        teamManager.setStatus(status)
                        showingPopover = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForStatus(status))
                                .frame(width: 8, height: 8)

                            Text(status.label)
                                .font(.caption)
                                .foregroundStyle(.white)

                            Spacer()

                            if status == teamManager.currentUserStatus {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(status == teamManager.currentUserStatus
                                  ? Color.white.opacity(0.08)
                                  : Color.clear)
                    )
                }
            }
            .padding(6)
            .frame(width: 180)
        }
    }

    private func colorForStatus(_ status: PresenceStatus) -> Color {
        switch status.dotColor {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
}
