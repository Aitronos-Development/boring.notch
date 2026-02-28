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
                    if vpnManager.isConnecting || vpnManager.isDisconnecting || vpnManager.serverBooting {
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
                    } else if vpnManager.isConnecting || vpnManager.serverBooting {
                        Spacer()
                        VpnConnectingProgressView(
                            elapsed: vpnManager.connectingElapsed,
                            maxSecs: vpnManager.serverBooting ? 135 : 30,
                            isBooting: vpnManager.serverBooting,
                            connectStage: vpnManager.connectStage,
                            serverName: vpnManager.serverName ?? vpnManager.profiles.first(where: { $0.status == "connecting" || $0.status == "authenticating" })?.displayName,
                            connectProgress: vpnManager.connectProgress,
                            connectDetail: vpnManager.connectDetail
                        )
                        .frame(maxWidth: .infinity)
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
                            if vpnManager.serverBooting || vpnManager.isConnecting || vpnManager.isDisconnecting {
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
                    .disabled(vpnManager.isConnecting || vpnManager.isDisconnecting || vpnManager.serverBooting)
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
        if vpnManager.serverBooting { return "Starting server..." }
        if vpnManager.isConnecting { return "Connecting..." }
        if vpnManager.isDisconnecting { return "Disconnecting..." }
        return vpnManager.isConnected ? "Connected" : "Disconnected"
    }

    private var statusColor: Color {
        if vpnManager.serverBooting || vpnManager.isConnecting || vpnManager.isDisconnecting { return .orange }
        return vpnManager.isConnected ? .green : .gray
    }

    private var buttonLabel: String {
        if vpnManager.serverBooting { return "Starting server..." }
        if vpnManager.isConnecting { return "Connecting..." }
        if vpnManager.isDisconnecting { return "Disconnecting..." }
        return vpnManager.isConnected ? "Disconnect" : "Connect"
    }

    private var buttonBackground: Color {
        if vpnManager.serverBooting || vpnManager.isConnecting || vpnManager.isDisconnecting {
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

                    // Upload filled area (blue)
                    SpeedAreaPath(samples: history.map(\.upMbps), maxY: maxY, width: w, height: h)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

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
        .animation(.easeInOut(duration: 0.4), value: history.count)
    }
}

// MARK: - Graph Paths

/// Catmull-Rom spline helper: generates smooth control points for a cubic Bezier
/// between p1 and p2, using p0 and p3 as neighboring anchors.
/// Tension 0 = Catmull-Rom, 0.5 = tighter. Matches Recharts "basis" curves.
private func catmullRomControlPoints(
    p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, tension: CGFloat = 0
) -> (CGPoint, CGPoint) {
    let t = (1 - tension) / 6
    let cp1 = CGPoint(
        x: p1.x + t * (p2.x - p0.x),
        y: p1.y + t * (p2.y - p0.y)
    )
    let cp2 = CGPoint(
        x: p2.x - t * (p3.x - p1.x),
        y: p2.y - t * (p3.y - p1.y)
    )
    return (cp1, cp2)
}

/// Convert samples to CGPoints for the graph
private func samplePoints(_ samples: [Double], maxY: Double, width: CGFloat, height: CGFloat) -> [CGPoint] {
    guard samples.count >= 2 else { return [] }
    let step = width / CGFloat(samples.count - 1)
    return samples.enumerated().map { (i, value) in
        let x = CGFloat(i) * step
        let y = height - (CGFloat(value / maxY) * height)
        return CGPoint(x: x, y: y)
    }
}

/// Add a smooth Catmull-Rom spline through points to the given path.
private func addSmoothCurve(to path: inout Path, points: [CGPoint]) {
    guard points.count >= 2 else { return }
    path.move(to: points[0])
    if points.count == 2 {
        path.addLine(to: points[1])
        return
    }
    for i in 0..<(points.count - 1) {
        let p0 = i > 0 ? points[i - 1] : points[i]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = (i + 2 < points.count) ? points[i + 2] : points[i + 1]
        let (cp1, cp2) = catmullRomControlPoints(p0: p0, p1: p1, p2: p2, p3: p3)
        path.addCurve(to: p2, control1: cp1, control2: cp2)
    }
}

private struct SpeedLinePath: Shape {
    let samples: [Double]
    let maxY: Double
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        let points = samplePoints(samples, maxY: maxY, width: width, height: height)
        guard points.count >= 2 else { return Path() }
        var path = Path()
        addSmoothCurve(to: &path, points: points)
        return path
    }
}

private struct SpeedAreaPath: Shape {
    let samples: [Double]
    let maxY: Double
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        let points = samplePoints(samples, maxY: maxY, width: width, height: height)
        guard points.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: points[0])
        // Add smooth curve through data points (skip the move — we already positioned)
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 0..<(points.count - 1) {
                let p0 = i > 0 ? points[i - 1] : points[i]
                let p1 = points[i]
                let p2 = points[i + 1]
                let p3 = (i + 2 < points.count) ? points[i + 2] : points[i + 1]
                let (cp1, cp2) = catmullRomControlPoints(p0: p0, p1: p1, p2: p2, p3: p3)
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
        path.addLine(to: CGPoint(x: points.last!.x, y: height))
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

// MARK: - Connecting Progress View

/// Unified fill-arc progress shown whenever VPN is connecting.
/// The ring fills over the max duration for the current stage, then spins
/// once full (matching the Hub overlay behavior).
private struct VpnConnectingProgressView: View {
    let elapsed: Int
    let maxSecs: Double
    let isBooting: Bool
    let connectStage: String
    let serverName: String?
    /// Deterministic progress from Hub: [current_step, total_steps]. [0, 0] = indeterminate.
    let connectProgress: [UInt32]
    /// Short detail for the current sub-step (e.g. "VM: STAGING", "Verify 3/10").
    let connectDetail: String

    /// Progress fraction: uses deterministic step/total when available, falls back to time-based.
    var progress: Double {
        let step = connectProgress.count >= 2 ? connectProgress[0] : 0
        let total = connectProgress.count >= 2 ? connectProgress[1] : 0
        if total > 0 {
            return min(Double(step) / Double(total), 1.0)
        }
        // Fallback: time-based estimate (only used when Hub hasn't reported progress yet)
        let stageMax: Double = {
            switch connectStage {
            case "setup": return 10
            case "server": return 135
            case "connecting": return 30
            case "verifying": return 12
            default: return maxSecs
            }
        }()
        return min(Double(elapsed) / stageMax, 0.95)
    }
    private var isFull: Bool { progress >= 0.99 }

    /// Continuous spin when the arc is full (waiting for stage to complete)
    @State private var spinAngle: Double = 0

    private struct StepDef {
        let key: String
        let label: String
        let icon: String
    }
    private let steps: [StepDef] = [
        StepDef(key: "setup",      label: "Setting up",       icon: "checkmark.shield"),
        StepDef(key: "server",     label: "Preparing server", icon: "server.rack"),
        StepDef(key: "connecting", label: "Connecting",       icon: "wifi"),
        StepDef(key: "verifying",  label: "Verifying",        icon: "checkmark.circle"),
    ]
    private var currentStepIndex: Int {
        steps.firstIndex(where: { $0.key == connectStage }) ?? 2
    }
    private var arcIcon: String {
        switch connectStage {
        case "setup":      return "checkmark.shield"
        case "server":     return "server.rack"
        case "verifying":  return "checkmark.circle"
        default:           return "shield.lefthalf.filled"
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            // Fill-arc ring — fills over stage duration, then spins when full
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 40, height: 40)
                if isFull {
                    // Spinner arc (partial ring rotating continuously)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(
                            Color.green.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(spinAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                spinAngle = 360
                            }
                        }
                } else {
                    // Fill arc (progress-based)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.green.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                }
                Image(systemName: arcIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(.green.opacity(0.85))
            }

            // 3-step stepper (same labels as Hub overlay)
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(idx < currentStepIndex
                                    ? Color.green.opacity(0.85)
                                    : idx == currentStepIndex
                                        ? Color.green.opacity(0.3)
                                        : Color.white.opacity(0.08))
                                .frame(width: 14, height: 14)
                            if idx < currentStepIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.black)
                            } else if idx == currentStepIndex {
                                Circle()
                                    .fill(Color.green.opacity(0.85))
                                    .frame(width: 5, height: 5)
                            } else {
                                Text("\(idx + 1)")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.gray.opacity(0.5))
                            }
                        }
                        Text(step.label)
                            .font(.system(size: 7))
                            .foregroundStyle(idx <= currentStepIndex
                                ? (idx == currentStepIndex ? Color.green.opacity(0.9) : Color.green.opacity(0.6))
                                : Color.gray.opacity(0.4))
                            .lineLimit(1)
                    }
                    if idx < steps.count - 1 {
                        Rectangle()
                            .fill(idx < currentStepIndex ? Color.green.opacity(0.5) : Color.white.opacity(0.1))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                            .offset(y: -5)
                    }
                }
            }
            .frame(maxWidth: 160)

            if let name = serverName {
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }

            if !connectDetail.isEmpty {
                Text(connectDetail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(1)
            } else if elapsed > 0 {
                Text("\(elapsed)s")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.gray.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
