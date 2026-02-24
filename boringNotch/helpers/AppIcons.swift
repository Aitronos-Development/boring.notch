//
//  AppIcons.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import SwiftUI
import AppKit

// MARK: - Thread-safe icon cache

/// Caches NSImage icons by bundle ID so NSWorkspace.iconForFile (which does a
/// synchronous XPC call to LaunchServices) is only invoked once per app.
/// NSCache is thread-safe by default.
private let _iconCache = NSCache<NSString, NSImage>()

/// Look up (or cache) an app icon for a bundle identifier.
/// Returns nil only when the bundle ID can't be resolved to a URL.
private func cachedIcon(for bundleID: String) -> NSImage? {
    let key = bundleID as NSString
    if let hit = _iconCache.object(forKey: key) { return hit }

    let workspace = NSWorkspace.shared
    guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
        return nil
    }
    let icon = workspace.icon(forFile: appURL.path)
    _iconCache.setObject(icon, forKey: key)
    return icon
}

struct AppIcons {

    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }

        return NSWorkspace.shared.icon(forFile: path)
    }

    func getIcon(bundleID: String) -> NSImage? {
        return cachedIcon(for: bundleID)
    }

    /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }

        return Bundle(url: url)
    }

}

// MARK: - SwiftUI view that loads the icon off the main thread

/// A SwiftUI `View` that shows the app icon for a bundle identifier.
/// The first load happens on a background thread so it never blocks the
/// main-thread view-body evaluation with a LaunchServices XPC roundtrip.
struct AppIconView: View {
    let bundleID: String
    @State private var resolved: NSImage?

    var body: some View {
        Group {
            if let img = resolved {
                Image(nsImage: img)
                    .resizable()
            } else {
                // Lightweight placeholder while loading
                Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable()
            }
        }
        .onAppear(perform: loadIcon)
        .onChange(of: bundleID) { _, _ in
            loadIcon()
        }
    }

    private func loadIcon() {
        // Fast path — already cached (no XPC call)
        if let hit = _iconCache.object(forKey: bundleID as NSString) {
            resolved = hit
            return
        }
        // Slow path — resolve off the main thread
        Task.detached(priority: .userInitiated) {
            let icon = cachedIcon(for: bundleID)
            await MainActor.run { resolved = icon }
        }
    }
}

/// Legacy convenience that returns a SwiftUI `Image` synchronously.
/// Now backed by the cache so repeated calls are free.
func AppIcon(for bundleID: String) -> Image {
    if let icon = cachedIcon(for: bundleID) {
        return Image(nsImage: icon)
    }
    return Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
}

func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    guard let icon = cachedIcon(for: bundleID) else { return nil }
    icon.size = NSSize(width: 256, height: 256)
    return icon
}
