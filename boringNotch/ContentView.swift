//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//  Last build: 2026-02-23
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var teamManager = TeamPresenceManager.shared
    @ObservedObject var timerManager = TimeTrackingManager.shared
    @ObservedObject var activeTaskManager = ActiveTaskManager.shared
    @ObservedObject var vpnManager = VpnManager.shared
    @ObservedObject var notificationManager = NotificationManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var tabSwitching: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var inactivityTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    @Default(.notchExpandedLayout) var notchExpandedLayout
    @Default(.notchExpandedHeight) var notchExpandedHeight
    @Default(.showCalendar) var showCalendar
    @Default(.showTimeTracking) var showTimeTracking

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var isMusicChinActive: Bool {
        (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
    }

    private var isTimerChinActive: Bool {
        !coordinator.expandingView.show && vm.notchState == .closed
            && (
                (timerManager.isTracking && timerManager.isLoaded)
                || activeTaskManager.activeTask != nil  // active task is cached — show even if Hub isn't loaded yet
            )
            && Defaults[.showTimerInClosedNotch] && !vm.hideOnClosed
    }

    private var isVpnTransitionChinActive: Bool {
        !coordinator.expandingView.show && vm.notchState == .closed
            && (vpnManager.isConnecting || vpnManager.isDisconnecting || vpnManager.serverBooting)
            && vpnManager.isLoaded
            && Defaults[.showVpnInClosedNotch] && !vm.hideOnClosed
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width
        let sideWidth = max(0, vm.effectiveClosedNotchHeight - 12)

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {
            chinWidth = 640
        } else if isMusicChinActive && isTimerChinActive {
            chinWidth += (2 * sideWidth + 60)
        } else if isMusicChinActive {
            chinWidth += (2 * sideWidth + 20)
        } else if isTimerChinActive {
            chinWidth += (2 * sideWidth + 60)
        } else if isVpnTransitionChinActive {
            chinWidth += (2 * sideWidth + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && teamManager.isLoaded && teamManager.onlineCount > 0
            && Defaults[.showTeamInClosedNotch] && !vm.hideOnClosed {
            chinWidth += (2 * sideWidth + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && !timerManager.isTracking
            && !(teamManager.isLoaded && teamManager.onlineCount > 0 && Defaults[.showTeamInClosedNotch])
            && vpnManager.isConnected && vpnManager.isLoaded
            && Defaults[.showVpnInClosedNotch] && !vm.hideOnClosed {
            chinWidth += (2 * sideWidth + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed {
            chinWidth += (2 * sideWidth + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )

                mainLayout
                    .modifier(NotchHeightModifier(
                        isOpen: vm.notchState == .open,
                        isFlexible: coordinator.currentView == .team || coordinator.currentView == .vpn || coordinator.currentView == .timeTracking,
                        height: vm.notchSize.height
                    ))
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive  {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                        // Manage inactivity timer: start when opened, cancel when closed
                        if newState == .open {
                            resetInactivityTimer()
                        } else {
                            inactivityTask?.cancel()
                            inactivityTask = nil
                        }
                    }
                    .onChange(of: coordinator.currentView) { _, _ in
                        // Resize when switching tabs while open (team view is taller)
                        if vm.notchState == .open {
                            // Suppress close + data-driven resizes during tab switch —
                            // the resize can momentarily move the content shape away
                            // from the cursor, and data observers firing during the
                            // animation cause overlapping springs → layout thrashing.
                            tabSwitching = true
                            withAnimation(animationSpring) {
                                vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
                            }
                            // Keep the guard active until the spring animation fully settles
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                tabSwitching = false
                            }
                        }
                    }
                    // Re-size the notch when time tracking data changes (content-hugging).
                    // Debounced: coalesce rapid publisher bursts into a single resize.
                    .onReceive(
                        ActiveTaskManager.shared.$activeTask
                            .map { $0 != nil }
                            .removeDuplicates()
                            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                    ) { _ in
                        resizeIfTimeTracking()
                    }
                    .onReceive(
                        NotchTimeSlotManager.shared.$slots
                            .map { $0.isEmpty }
                            .removeDuplicates()
                            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                    ) { _ in
                        resizeIfTimeTracking()
                    }
                    .onReceive(
                        TimeTrackingManager.shared.$recentTasks
                            .map { $0.count }
                            .removeDuplicates()
                            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                    ) { _ in
                        resizeIfTimeTracking()
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .onChange(of: notificationManager.newlyArrivedNotification?.id) { _, newId in
                        handleNewNotificationArrival()
                    }
                    .contextMenu {
                        Button("Settings") {
                            SettingsWindowController.shared.showWindow()
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }

            // Notification toast is now shown in a separate window
            // via NotificationToastWindowController (independent of Notch state)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: activeWindowMaxHeight, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        // Live-update the notch size when layout settings change while open
        .onChange(of: notchExpandedLayout) { _, _ in
            if vm.notchState == .open {
                withAnimation(animationSpring) {
                    vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
                }
            }
        }
        .onChange(of: notchExpandedHeight) { _, _ in
            if vm.notchState == .open {
                withAnimation(animationSpring) {
                    vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
                }
            }
        }
        .onChange(of: showCalendar) { _, _ in
            if vm.notchState == .open {
                withAnimation(animationSpring) {
                    vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
                }
            }
        }
        .onChange(of: showTimeTracking) { _, _ in
            if vm.notchState == .open {
                withAnimation(animationSpring) {
                    vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
                }
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .home
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if isMusicChinActive && isTimerChinActive {
                          CombinedMusicTimerChin()
                              .frame(alignment: .center)
                      } else if isMusicChinActive {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if isTimerChinActive {
                          TimerLiveActivity()
                              .frame(alignment: .center)
                      } else if isVpnTransitionChinActive {
                          VpnConnectingChin()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && teamManager.isLoaded && teamManager.onlineCount > 0 && Defaults[.showTeamInClosedNotch] && !vm.hideOnClosed {
                          TeamSneakPeek()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed
                          && (!musicManager.isPlaying && musicManager.isPlayerIdle) && !timerManager.isTracking
                          && !(teamManager.isLoaded && teamManager.onlineCount > 0 && Defaults[.showTeamInClosedNotch])
                          && vpnManager.isConnected && vpnManager.isLoaded
                          && Defaults[.showVpnInClosedNotch] && !vm.hideOnClosed {
                          VpnSneakPeek()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack(spacing: 0) {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .team:
                        NotchTeamView()
                    case .vpn:
                        NotchVpnView()
                    case .timeTracking:
                        NotchTimelineView()
                    }
                    Spacer(minLength: 0)
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func TeamSneakPeek() -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                Text("\(teamManager.onlineCount) online")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            HStack(spacing: 4) {
                Circle()
                    .fill(sneakPeekStatusColor)
                    .frame(width: 6, height: 6)
                Text(teamManager.currentUserStatus.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var sneakPeekStatusColor: Color {
        switch teamManager.currentUserStatus.dotColor {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }

    @ViewBuilder
    func VpnSneakPeek() -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
                Text(vpnManager.downSpeedMbps)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
                Text(vpnManager.upSpeedMbps)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func VpnConnectingChin() -> some View {
        let isBooting = vpnManager.serverBooting
        let maxSecs: Double = isBooting ? 135 : 30
        let elapsed = vpnManager.connectingElapsed
        let progress = min(Double(elapsed) / maxSecs, 0.99)

        HStack {
            HStack(spacing: 4) {
                // Fill-arc for booting/connecting; spinner for disconnecting
                if isBooting || vpnManager.isConnecting {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                    }
                    .frame(width: 10, height: 10)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                }
                Image(systemName: isBooting ? "server.rack" : "shield.lefthalf.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(vpnManager.isDisconnecting ? .orange : .green)
            }
            .frame(width: max(0, vm.effectiveClosedNotchHeight - 12))

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(isBooting ? "Starting server..." : (vpnManager.isConnecting ? "Connecting..." : "Disconnecting..."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(vpnManager.isDisconnecting ? .orange : .green)
                if (isBooting || vpnManager.isConnecting) && elapsed > 0 {
                    // Thin fill progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 2)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.green.opacity(0.7))
                                .frame(width: geo.size.width * progress, height: 2)
                                .animation(.linear(duration: 1), value: progress)
                        }
                    }
                    .frame(height: 2)
                }
            }
            .frame(width: max(0, vm.effectiveClosedNotchHeight + 30), alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func TimerLiveActivity() -> some View {
        let isAutoTracking = !timerManager.isTracking && activeTaskManager.activeTask != nil
        let elapsed = isAutoTracking
            ? activeTaskManager.elapsedFormatted
            : timerManager.elapsedFormatted

        let notchW = vm.closedNotchSize.width + -cornerRadiusInsets.closed.top
        HStack(spacing: 0) {
            // Left: status indicator — fixed padding from notch edge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Image(systemName: isAutoTracking ? "bolt.fill" : "timer")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)

            // Middle: notch black gap
            Rectangle()
                .fill(.black)
                .frame(width: notchW)

            // Right: elapsed — grows with content, padding keeps it off the edge
            Text(elapsed)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
                .fixedSize()
                .padding(.horizontal, 8)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func CombinedMusicTimerChin() -> some View {
        let isAutoTracking = !timerManager.isTracking && activeTaskManager.activeTask != nil
        let elapsed = isAutoTracking
            ? activeTaskManager.elapsedFormatted
            : timerManager.elapsedFormatted
        let sideW2 = max(0, vm.effectiveClosedNotchHeight - 12)
        let notchW2 = vm.closedNotchSize.width + -cornerRadiusInsets.closed.top

        HStack(spacing: 0) {
            // Left: music visualizer (same as MusicLiveActivity right side)
            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(Defaults[.coloredSpectrogram]
                            ? Color(nsColor: musicManager.avgColor).gradient
                            : Color.gray.gradient)
                        .frame(width: sideW2, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Middle: notch black gap
            Rectangle()
                .fill(.black)
                .frame(width: notchW2)

            // Right: elapsed — grows with content
            Text(elapsed)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
                .fixedSize()
                .padding(.horizontal, 8)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private var activeOpenHeight: CGFloat {
        switch coordinator.currentView {
        case .team: return Defaults[.teamMaxNotchHeight]
        case .vpn: return 280
        case .timeTracking:
            return NotchTimelineView.idealHeight(
                hasActiveTask: ActiveTaskManager.shared.activeTask != nil,
                hasSlots: !NotchTimeSlotManager.shared.slots.isEmpty,
                recentTaskCount: timerManager.recentTasks.count
            )
        default:
            let customHeight = Defaults[.notchExpandedHeight]
            // User has adjusted the height slider
            if customHeight > openNotchSize.height {
                return customHeight
            }
            // Stacked layout with both panels needs extra height
            if Defaults[.notchExpandedLayout] == .stacked
                && Defaults[.showCalendar]
                && Defaults[.showTimeTracking]
                && (timerManager.isTracking || TimeSlotSummaryManager.shared.hasPendingSlots || ActiveTaskManager.shared.activeTask != nil) {
                return 210
            }
            return openNotchSize.height
        }
    }

    /// Fixed window max height — always large enough for the tallest content.
    /// Using a constant prevents the outer frame from shifting when switching tabs.
    private var activeWindowMaxHeight: CGFloat {
        500 + shadowPadding
    }


    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open(height: activeOpenHeight)
        }
    }

    // MARK: - Inactivity Timer

    /// After 30 seconds of no hover activity while the notch is open,
    /// automatically switch back to the home tab.
    private func resetInactivityTimer() {
        inactivityTask?.cancel()
        inactivityTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if vm.notchState == .open && coordinator.currentView != .home {
                withAnimation(.smooth) {
                    coordinator.currentView = .home
                }
            }
        }
    }

    /// Re-adjust notch height when time tracking content changes (data loads, task selected/cleared).
    /// Suppressed during tab switch animation to prevent overlapping animations / layout thrashing.
    private func resizeIfTimeTracking() {
        guard vm.notchState == .open,
              coordinator.currentView == .timeTracking,
              !tabSwitching else { return }
        withAnimation(animationSpring) {
            vm.notchSize = CGSize(width: openNotchSize.width, height: activeOpenHeight)
        }
    }

    // MARK: - Notification Handling

    private func handleNewNotificationArrival() {
        // Toast + effects are now handled by NotificationToastWindowController
        // (triggered from NotificationManager.fetchNotifications)
        notificationManager.clearNewArrival()
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            // Reset inactivity timer on any interaction
            if vm.notchState == .open {
                resetInactivityTimer()
            }
            withAnimation(animationSpring) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }

                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    // Don't close during tab switch — resize can briefly
                    // move the content shape away from the cursor
                    guard !self.tabSwitching else { return }

                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose {
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

/// Applies fixed height for non-team views, maxHeight for team view (content-sized).
/// Uses a single view identity so SwiftUI can animate smoothly between states.
private struct NotchHeightModifier: ViewModifier {
    let isOpen: Bool
    let isFlexible: Bool
    let height: CGFloat

    func body(content: Content) -> some View {
        // When closed: no constraints (nil/nil → intrinsic size)
        // When open + flexible (team/vpn): minHeight nil, maxHeight = height (content-sized, capped)
        // When open + other: minHeight = height, maxHeight = height (fixed)
        let minH: CGFloat? = isOpen && !isFlexible ? height : nil
        let maxH: CGFloat? = isOpen ? height : nil
        content.frame(minHeight: minH, maxHeight: maxH)
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
