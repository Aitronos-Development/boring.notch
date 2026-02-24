//
//  FullScreenEffectView.swift
//  boringNotch
//
//  Full-screen particle effects for notification announcements.
//  Uses CAEmitterLayer for performant GPU-accelerated particles.
//

import AppKit
import SwiftUI

// MARK: - Effect Types

enum NotificationEffectType: String {
    case confetti
    case hearts
    case fireworks
    case spotlight
    case celebration

    var duration: TimeInterval {
        switch self {
        case .confetti: return 6.0
        case .hearts: return 6.0
        case .fireworks: return 4.5
        case .spotlight: return 4.5
        case .celebration: return 7.0
        }
    }
}

// MARK: - Emitter NSView

class EffectEmitterNSView: NSView {
    private var emitterLayers: [CAEmitterLayer] = []
    private var effectType: NotificationEffectType = .confetti

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(effect: NotificationEffectType) {
        self.effectType = effect
        clearLayers()

        switch effect {
        case .confetti:
            setupConfetti()
        case .hearts:
            setupHearts()
        case .fireworks:
            setupFireworks()
        case .spotlight:
            setupSpotlight()
        case .celebration:
            setupGoldenRain()
            setupRisingStars()
        }

        // Auto-stop emission after a portion of the duration (particles continue falling).
        // Spotlight manages its own lifecycle via sweep animations.
        if effect == .spotlight { return }
        let stopDelay = effect == .fireworks ? 1.5 : effect.duration * 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay) { [weak self] in
            self?.stopEmission()
        }
    }

    private func clearLayers() {
        emitterLayers.forEach { $0.removeFromSuperlayer() }
        emitterLayers.removeAll()
    }

    private func stopEmission() {
        for layer in emitterLayers {
            layer.emitterCells?.forEach { $0.birthRate = 0 }
        }
    }

    // MARK: - Confetti

    private func setupConfetti() {
        // macOS non-flipped NSView: Y goes UP. bounds.maxY = top edge.
        // Cannon from top-left corner, shooting right+down
        addConfettiCannon(
            at: CGPoint(x: -20, y: bounds.maxY + 20),
            longitude: -.pi / 5    // ~36° below rightward
        )
        // Cannon from top-right corner, shooting left+down
        addConfettiCannon(
            at: CGPoint(x: bounds.maxX + 20, y: bounds.maxY + 20),
            longitude: .pi + .pi / 5  // ~36° below leftward
        )
        // Center top rain to fill the middle
        addConfettiCannon(
            at: CGPoint(x: bounds.midX, y: bounds.maxY + 20),
            longitude: 3 * .pi / 2    // straight down
        )
    }

    private func addConfettiCannon(at position: CGPoint, longitude: CGFloat) {
        let colors: [NSColor] = [
            .systemBlue, .systemPink, .systemYellow, .systemGreen,
            .systemOrange, .systemPurple, .systemCyan, .systemRed
        ]

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.emitterPosition = position
        emitter.renderMode = .additive

        var cells: [CAEmitterCell] = []
        for color in colors {
            let cell = CAEmitterCell()
            cell.contents = makeRectImage(color: color, size: CGSize(width: 14, height: 8))
            cell.birthRate = 30
            cell.lifetime = 7
            cell.velocity = 500
            cell.velocityRange = 200
            cell.emissionLongitude = longitude
            cell.emissionRange = .pi / 3   // 60° spread
            cell.spin = 4
            cell.spinRange = 6
            cell.scale = 1.0
            cell.scaleRange = 0.5
            cell.yAcceleration = -300      // gravity (Y goes UP, so negative = down)
            cell.alphaSpeed = -0.1
            cells.append(cell)

            let strip = CAEmitterCell()
            strip.contents = makeRectImage(color: color, size: CGSize(width: 18, height: 4))
            strip.birthRate = 20
            strip.lifetime = 6
            strip.velocity = 450
            strip.velocityRange = 150
            strip.emissionLongitude = longitude
            strip.emissionRange = .pi / 3
            strip.spin = 5
            strip.spinRange = 8
            strip.scale = 0.8
            strip.scaleRange = 0.4
            strip.yAcceleration = -280
            strip.alphaSpeed = -0.12
            cells.append(strip)
        }

        emitter.emitterCells = cells
        emitter.frame = bounds
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)
    }

    // MARK: - Hearts

    private func setupHearts() {
        // Emit from below the bottom edge, float upward
        // Y goes UP on macOS, so bounds.minY (= 0) is the bottom
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY - 40)
        emitter.emitterSize = CGSize(width: bounds.width * 1.3, height: 1)

        let colors: [NSColor] = [
            NSColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 1),
            NSColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1),
            NSColor(red: 0.9, green: 0.1, blue: 0.3, alpha: 1),
            NSColor(red: 1.0, green: 0.6, blue: 0.7, alpha: 1),
        ]

        var cells: [CAEmitterCell] = []
        for color in colors {
            let cell = CAEmitterCell()
            cell.contents = makeHeartImage(color: color)
            cell.birthRate = 18
            cell.lifetime = 7
            cell.velocity = 200
            cell.velocityRange = 80
            cell.emissionLongitude = .pi / 2  // upward (+Y)
            cell.emissionRange = .pi / 3
            cell.spin = 0.5
            cell.spinRange = 1.0
            cell.scale = 0.35
            cell.scaleRange = 0.2
            cell.yAcceleration = -30          // gravity slows them down then pulls back
            cell.alphaSpeed = -0.12
            cells.append(cell)
        }

        emitter.emitterCells = cells
        emitter.frame = bounds
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)
    }

    // MARK: - Fireworks

    private func setupFireworks() {
        let burstCount = 6
        let colors: [NSColor] = [.systemYellow, .systemCyan, .systemPink, .systemGreen, .systemOrange, .systemBlue]

        for i in 0..<burstCount {
            let delay = Double(i) * 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                let x = CGFloat.random(in: self.bounds.width * 0.1...self.bounds.width * 0.9)
                let y = CGFloat.random(in: self.bounds.height * 0.25...self.bounds.height * 0.75)
                self.addFireworkBurst(at: CGPoint(x: x, y: y), color: colors[i % colors.count])
            }
        }
    }

    private func addFireworkBurst(at point: CGPoint, color: NSColor) {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.emitterPosition = point
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.contents = makeCircleImage(color: color, size: 10)
        cell.birthRate = 150          // was 500 — much lighter
        cell.lifetime = 1.8           // was 2.5 — shorter trails
        cell.velocity = 300           // was 400 — tighter bursts
        cell.velocityRange = 120
        cell.emissionRange = .pi * 2
        cell.scale = 0.45
        cell.scaleRange = 0.25
        cell.scaleSpeed = -0.15       // shrink faster
        cell.alphaSpeed = -0.5        // fade faster
        cell.yAcceleration = -120     // lighter gravity

        emitter.emitterCells = [cell]  // no trail sub-cells — big perf win
        emitter.frame = bounds
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)

        // Very short burst — stop after 0.12s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            cell.birthRate = 0
        }
    }

    // MARK: - Spotlight

    private func setupSpotlight() {
        // Two particle-based light beams sweeping across the screen.
        // Each beam is a narrow-cone emitter that shoots soft glowing
        // particles downward, creating a visible "searchlight" effect.

        addSpotlightBeam(
            startX: -bounds.width * 0.1,
            endX: bounds.width * 1.1,
            delay: 0.0,
            duration: 2.8,
            color: NSColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1)  // warm gold
        )
        addSpotlightBeam(
            startX: bounds.width * 1.1,
            endX: -bounds.width * 0.1,
            delay: 0.4,
            duration: 2.4,
            color: NSColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1)  // cool blue-white
        )
    }

    private func addSpotlightBeam(startX: CGFloat, endX: CGFloat, delay: TimeInterval, duration: TimeInterval, color: NSColor) {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        // Start at top of screen
        emitter.emitterPosition = CGPoint(x: startX, y: bounds.maxY + 10)
        emitter.renderMode = .additive

        // Large soft glow particles shooting downward in a narrow cone
        let glow = CAEmitterCell()
        glow.contents = makeSoftGlowImage(color: color, size: 80)
        glow.birthRate = 60
        glow.lifetime = 1.2
        glow.velocity = 600
        glow.velocityRange = 100
        glow.emissionLongitude = -.pi / 2  // downward
        glow.emissionRange = .pi / 16      // very narrow cone (~11°)
        glow.scale = 1.2
        glow.scaleRange = 0.4
        glow.scaleSpeed = 0.3              // grow as they travel
        glow.alphaSpeed = -0.7
        glow.spin = 0

        // Smaller bright core particles
        let core = CAEmitterCell()
        core.contents = makeSoftGlowImage(color: .white, size: 40)
        core.birthRate = 30
        core.lifetime = 0.8
        core.velocity = 650
        core.velocityRange = 80
        core.emissionLongitude = -.pi / 2
        core.emissionRange = .pi / 20
        core.scale = 0.6
        core.scaleRange = 0.2
        core.alphaSpeed = -1.0

        emitter.emitterCells = [glow, core]
        emitter.frame = bounds
        emitter.opacity = 0
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)

        // Animate: fade in, sweep position, fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            emitter.opacity = 1

            let sweep = CABasicAnimation(keyPath: "emitterPosition.x")
            sweep.fromValue = startX
            sweep.toValue = endX
            sweep.duration = duration
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sweep.fillMode = .forwards
            sweep.isRemovedOnCompletion = false
            emitter.add(sweep, forKey: "sweep")

            // Fade out near the end
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8) {
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1
                fadeOut.toValue = 0
                fadeOut.duration = duration * 0.25
                fadeOut.fillMode = .forwards
                fadeOut.isRemovedOnCompletion = false
                emitter.add(fadeOut, forKey: "fadeOut")
            }
        }
    }

    private func makeSoftGlowImage(color: NSColor, size: CGFloat) -> CGImage? {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let components = color.cgColor.components ?? [1, 1, 1, 1]
            let r = components[0], g = components[1], b = components[2]
            let colors = [
                CGColor(colorSpace: colorSpace, components: [r, g, b, 0.6])!,
                CGColor(colorSpace: colorSpace, components: [r, g, b, 0.15])!,
                CGColor(colorSpace: colorSpace, components: [r, g, b, 0.0])!,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.4, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Golden Rain (for celebration — top-down metallic shimmer)

    private func setupGoldenRain() {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 20)
        emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)

        let golds: [NSColor] = [
            NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1),   // gold
            NSColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1),   // amber
            NSColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1), // dark gold
            NSColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1),  // light gold
        ]

        var cells: [CAEmitterCell] = []
        for color in golds {
            let cell = CAEmitterCell()
            cell.contents = makeRectImage(color: color, size: CGSize(width: 12, height: 6))
            cell.birthRate = 25
            cell.lifetime = 5
            cell.velocity = 120
            cell.velocityRange = 60
            cell.emissionLongitude = -.pi / 2  // downward
            cell.emissionRange = .pi / 6
            cell.spin = 3
            cell.spinRange = 5
            cell.scale = 0.9
            cell.scaleRange = 0.4
            cell.yAcceleration = -200
            cell.alphaSpeed = -0.15
            cells.append(cell)
        }

        emitter.emitterCells = cells
        emitter.frame = bounds
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)
    }

    // MARK: - Rising Stars (for celebration — upward-floating sparkle stars)

    private func setupRisingStars() {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY - 20)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.renderMode = .additive

        let starColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1),  // warm white
            NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),  // gold
            .white,
        ]

        var cells: [CAEmitterCell] = []
        for color in starColors {
            let cell = CAEmitterCell()
            cell.contents = makeStarImage(color: color, size: 20)
            cell.birthRate = 8
            cell.lifetime = 5
            cell.velocity = 100
            cell.velocityRange = 50
            cell.emissionLongitude = .pi / 2   // upward
            cell.emissionRange = .pi / 4
            cell.spin = 1.5
            cell.spinRange = 3
            cell.scale = 0.3
            cell.scaleRange = 0.2
            cell.scaleSpeed = -0.03
            cell.alphaSpeed = -0.15
            cell.yAcceleration = -15           // gentle counter-gravity
            cells.append(cell)
        }

        emitter.emitterCells = cells
        emitter.frame = bounds
        layer?.addSublayer(emitter)
        emitterLayers.append(emitter)
    }

    // MARK: - Image Generators

    private func makeRectImage(color: NSColor, size: CGSize) -> CGImage? {
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func makeCircleImage(color: NSColor, size: CGFloat) -> CGImage? {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func makeHeartImage(color: NSColor) -> CGImage? {
        let size = NSSize(width: 40, height: 40)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            let w = rect.width
            let h = rect.height

            path.move(to: NSPoint(x: w * 0.5, y: h * 0.9))
            path.curve(to: NSPoint(x: w * 0.1, y: h * 0.55),
                        controlPoint1: NSPoint(x: w * 0.5, y: h * 0.75),
                        controlPoint2: NSPoint(x: w * 0.1, y: h * 0.75))
            path.curve(to: NSPoint(x: w * 0.5, y: h * 0.2),
                        controlPoint1: NSPoint(x: w * 0.1, y: h * 0.3),
                        controlPoint2: NSPoint(x: w * 0.35, y: h * 0.2))
            path.curve(to: NSPoint(x: w * 0.9, y: h * 0.55),
                        controlPoint1: NSPoint(x: w * 0.65, y: h * 0.2),
                        controlPoint2: NSPoint(x: w * 0.9, y: h * 0.3))
            path.curve(to: NSPoint(x: w * 0.5, y: h * 0.9),
                        controlPoint1: NSPoint(x: w * 0.9, y: h * 0.75),
                        controlPoint2: NSPoint(x: w * 0.5, y: h * 0.75))
            path.close()

            color.setFill()
            path.fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func makeStarImage(color: NSColor, size: CGFloat) -> CGImage? {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let path = NSBezierPath()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let outerR = rect.width / 2
            let innerR = outerR * 0.4
            let points = 4

            for i in 0..<(points * 2) {
                let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let r = i.isMultiple(of: 2) ? outerR : innerR
                let pt = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
            }
            path.close()
            color.setFill()
            path.fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Re-position emitters if resized
        for layer in emitterLayers {
            layer.frame = bounds
        }
    }
}

// MARK: - SwiftUI Wrapper

struct EffectEmitterView: NSViewRepresentable {
    let effectType: NotificationEffectType

    func makeNSView(context: Context) -> EffectEmitterNSView {
        let view = EffectEmitterNSView()
        view.configure(effect: effectType)
        return view
    }

    func updateNSView(_ nsView: EffectEmitterNSView, context: Context) {}
}

// MARK: - Full-Screen Effect Window Controller

@MainActor
final class EffectWindowController {
    static let shared = EffectWindowController()

    private var effectWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showEffect(_ effectName: String) {
        guard let effectType = NotificationEffectType(rawValue: effectName) else {
            print("[Effects] Unknown effect type: \(effectName)")
            return
        }
        showEffect(effectType)
    }

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

    func showEffect(_ effectType: NotificationEffectType) {
        // Dismiss any existing effect
        dismissEffect()

        guard let screen = notchScreen else { return }
        let screenFrame = screen.frame

        let window = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .mainMenu + 5 // Toast +3, backdrop +4, effects +5, modal +6
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Use EffectEmitterNSView directly (not NSHostingView) so that bounds
        // are non-zero before configure() runs. NSHostingView performs layout
        // asynchronously, causing configure() to see bounds of .zero and placing
        // all emitters at the bottom-left corner.
        let effectView = EffectEmitterNSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        window.contentView = effectView
        window.setFrame(screenFrame, display: true)
        window.orderFrontRegardless()

        // Configure AFTER frame is fully set so bounds are correct
        effectView.configure(effect: effectType)

        self.effectWindow = window

        // Auto-dismiss after effect duration
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(effectType.duration))
            await MainActor.run { [weak self] in
                self?.dismissEffect()
            }
        }

        print("[Effects] Showing \(effectType.rawValue) effect (duration: \(effectType.duration)s)")
    }

    func dismissEffect() {
        dismissTask?.cancel()
        dismissTask = nil

        if let window = effectWindow {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                window.orderOut(nil)
                window.close()
                self?.effectWindow = nil
            })
        }
    }
}
