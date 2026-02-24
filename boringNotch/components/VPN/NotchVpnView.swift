//
//  NotchVpnView.swift
//  boringNotch
//
//  VPN tab view for the notch — shows connection status, server picker,
//  speed graph, and connect/disconnect controls.
//

import SwiftUI

@MainActor
struct NotchVpnView: View {
    @ObservedObject var vpnManager = VpnManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("VPN")
                    .font(.headline)
                    .foregroundStyle(.white)

                // Environment badge
                if vpnManager.isLoaded && vpnManager.serverReachable {
                    Text(vpnManager.environment == "local" ? "Local" : "Production")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(vpnManager.environment == "local" ? .orange : .green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (vpnManager.environment == "local" ? Color.orange : Color.green)
                                .opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // IP allowlist indicator (only when connected and public IP is available)
                if vpnManager.isConnected, let ip = vpnManager.publicIp {
                    HStack(spacing: 3) {
                        Image(systemName: vpnManager.isAllowlisted ? "checkmark.shield.fill" : "exclamationmark.shield")
                            .font(.system(size: 8))
                            .foregroundStyle(vpnManager.isAllowlisted ? .green : .orange)
                        Text(ip)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(vpnManager.isAllowlisted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    if vpnManager.isConnecting || vpnManager.isDisconnecting {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                    } else {
                        Circle()
                            .fill(vpnManager.isConnected ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Divider()
                .background(Color.gray.opacity(0.3))

            // Content
            if !vpnManager.isLoaded || !vpnManager.serverReachable {
                VStack(spacing: 8) {
                    if vpnManager.isLoaded && !vpnManager.serverReachable {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange.opacity(0.6))
                        Text("Hub not reachable")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text("Start the Hub app to manage VPN")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray.opacity(0.6))
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Connecting to Hub...")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vpnManager.vpnServiceOnline {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange.opacity(0.6))
                    Text("VPN service offline")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(environmentHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.gray.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    // Server picker
                    serverPicker

                    // Speed graph (when connected and has history)
                    if vpnManager.isConnected {
                        SpeedGraphView(history: vpnManager.speedHistory)
                            .frame(height: 80)
                            .frame(maxWidth: .infinity)

                        // Current speed + traffic row
                        HStack(spacing: 0) {
                            SpeedIndicator(icon: "arrow.down", value: vpnManager.downSpeedMbps)
                            Spacer()
                            SpeedIndicator(icon: "arrow.up", value: vpnManager.upSpeedMbps)
                            Spacer()
                            TrafficIndicator(label: "Session", recv: vpnManager.sessionRecvFormatted, sent: vpnManager.sessionSentFormatted)
                        }
                        .frame(maxWidth: .infinity)
                    } else if vpnManager.isConnecting {
                        // Connecting: show progress indicator
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                            .scaleEffect(0.8)
                            .frame(maxWidth: .infinity)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                        if let name = vpnManager.serverName ?? vpnManager.profiles.first(where: { $0.status == "connecting" })?.displayName {
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity)
                        }
                        Spacer()
                    } else {
                        // Disconnected: centered shield icon
                        Spacer()
                        Image(systemName: "shield.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.4))
                            .frame(maxWidth: .infinity)
                        Text("Not Connected")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }

                    Spacer(minLength: 2)

                    // Connect / Disconnect button
                    Button(action: {
                        if vpnManager.isConnected {
                            vpnManager.disconnect()
                        } else {
                            vpnManager.connect()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if vpnManager.isConnecting || vpnManager.isDisconnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: vpnManager.isConnected ? "xmark.shield" : "checkmark.shield")
                                    .font(.system(size: 11))
                            }
                            Text(buttonLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(buttonBackground)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(vpnManager.isConnecting || vpnManager.isDisconnecting)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Server Picker

    private var serverPicker: some View {
        Menu {
            Button(action: { vpnManager.selectedProfileId = nil }) {
                HStack {
                    Text("Auto (nearest)")
                    if vpnManager.selectedProfileId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(vpnManager.profiles.filter { $0.synced == true }) { profile in
                Button(action: { vpnManager.selectedProfileId = profile.id }) {
                    HStack {
                        Text(profile.displayName)
                        if profile.status == "connected" {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        if vpnManager.selectedProfileId == profile.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vpnManager.isConnected ? "shield.lefthalf.filled" : "shield")
                    .font(.system(size: 10))
                    .foregroundStyle(vpnManager.isConnected ? .green : .gray)
                Text(selectedServerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
    }

    private var selectedServerLabel: String {
        if vpnManager.isConnected, let name = vpnManager.serverName {
            return name
        }
        if let id = vpnManager.selectedProfileId,
           let profile = vpnManager.profiles.first(where: { $0.id == id }) {
            return profile.displayName
        }
        return "Auto (nearest)"
    }

    // MARK: - Computed Labels

    private var environmentHint: String {
        if vpnManager.environment == "local" {
            return "Local VPN daemon is not running\nRun: ./start-dev.sh vpn"
        } else if vpnManager.environment == "production" {
            return "Production VPN service is not reachable"
        }
        return "The VPN daemon is not running"
    }

    private var statusLabel: String {
        if vpnManager.isConnecting { return "Connecting..." }
        if vpnManager.isDisconnecting { return "Disconnecting..." }
        return vpnManager.isConnected ? "Connected" : "Disconnected"
    }

    private var statusColor: Color {
        if vpnManager.isConnecting { return .orange }
        if vpnManager.isDisconnecting { return .orange }
        return vpnManager.isConnected ? .green : .gray
    }

    private var buttonLabel: String {
        if vpnManager.isConnecting { return "Connecting..." }
        if vpnManager.isDisconnecting { return "Disconnecting..." }
        return vpnManager.isConnected ? "Disconnect" : "Connect"
    }

    private var buttonBackground: Color {
        if vpnManager.isConnecting || vpnManager.isDisconnecting {
            return .gray.opacity(0.3)
        }
        return vpnManager.isConnected ? .red.opacity(0.6) : .green.opacity(0.6)
    }
}

// MARK: - Speed Graph

private struct SpeedGraphView: View {
    let history: [SpeedSample]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if history.count < 2 {
                // Not enough data for a graph
                VStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("Collecting data...")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxDown = max(history.map(\.downMbps).max() ?? 1, 0.1)
                let maxUp = max(history.map(\.upMbps).max() ?? 1, 0.1)
                let maxY = max(maxDown, maxUp) * 1.1 // 10% headroom

                ZStack(alignment: .topTrailing) {
                    // Download filled area (green)
                    SpeedAreaPath(samples: history.map(\.downMbps), maxY: maxY, width: w, height: h)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.3), Color.green.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Download line
                    SpeedLinePath(samples: history.map(\.downMbps), maxY: maxY, width: w, height: h)
                        .stroke(Color.green.opacity(0.8), lineWidth: 1.5)

                    // Upload line (thinner, blue)
                    SpeedLinePath(samples: history.map(\.upMbps), maxY: maxY, width: w, height: h)
                        .stroke(Color.blue.opacity(0.6), lineWidth: 1)

                    // Legend
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f Mbps", maxY))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.gray.opacity(0.5))
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Circle().fill(.green.opacity(0.8)).frame(width: 4, height: 4)
                                Text("Down")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.gray.opacity(0.6))
                            }
                            HStack(spacing: 3) {
                                Circle().fill(.blue.opacity(0.6)).frame(width: 4, height: 4)
                                Text("Up")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.gray.opacity(0.6))
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Graph Paths

private struct SpeedLinePath: Shape {
    let samples: [Double]
    let maxY: Double
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        guard samples.count >= 2 else { return Path() }
        var path = Path()
        let step = width / CGFloat(samples.count - 1)

        for (i, value) in samples.enumerated() {
            let x = CGFloat(i) * step
            let y = height - (CGFloat(value / maxY) * height)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private struct SpeedAreaPath: Shape {
    let samples: [Double]
    let maxY: Double
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        guard samples.count >= 2 else { return Path() }
        var path = Path()
        let step = width / CGFloat(samples.count - 1)

        path.move(to: CGPoint(x: 0, y: height))

        for (i, value) in samples.enumerated() {
            let x = CGFloat(i) * step
            let y = height - (CGFloat(value / maxY) * height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: CGFloat(samples.count - 1) * step, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Helper Subviews

private struct SpeedIndicator: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            Text("Mbps")
                .font(.system(size: 7))
                .foregroundStyle(.gray)
        }
    }
}

private struct TrafficIndicator: View {
    let label: String
    let recv: String
    let sent: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 7))
                .foregroundStyle(.gray)
            Text("\(recv) / \(sent)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
