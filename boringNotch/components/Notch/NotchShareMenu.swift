//
//  NotchShareMenu.swift
//  boringNotch
//
//  Share popover: AirDrop + SecurePaste
//

import AppKit
import SwiftUI

struct NotchShareMenu: View {
    @StateObject private var quickShare = QuickShareService.shared
    @ObservedObject private var navManager = HubNavigationManager.shared
    @State private var hostView: NSView?

    enum ShareMode {
        case picker    // Initial: AirDrop vs SecurePaste
        case securePaste
    }

    @State private var mode: ShareMode = .picker
    @State private var securePasteContent = ""
    @State private var burnAfterReading = false
    @State private var isCreating = false
    @State private var resultURL: String?
    @State private var copied = false
    @State private var errorMessage: String?
    @State private var inputMode: SecurePasteInputMode = .text

    enum SecurePasteInputMode {
        case text, file
    }

    private var airdropProvider: QuickShareProvider? {
        quickShare.availableProviders.first(where: { $0.id == "AirDrop" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch mode {
            case .picker:
                pickerView
            case .securePaste:
                securePasteView
            }
        }
        .frame(width: 220)
        .background(NSViewHost(view: $hostView))
    }

    // MARK: - Picker View

    private var pickerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.top, 10)

            HStack(spacing: 8) {
                // AirDrop
                Button {
                    if let provider = airdropProvider {
                        Task {
                            await quickShare.showFilePicker(for: provider, from: hostView)
                        }
                    }
                } label: {
                    shareCard(
                        icon: airdropProvider?.imageData,
                        systemIcon: "wifi",
                        label: "AirDrop"
                    )
                }
                .buttonStyle(ShareCardButtonStyle())

                // Secure Paste
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        mode = .securePaste
                    }
                } label: {
                    shareCard(
                        icon: nil,
                        systemIcon: "lock.fill",
                        label: "Secure Paste"
                    )
                }
                .buttonStyle(ShareCardButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func shareCard(icon: Data?, systemIcon: String, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                if let imgData = icon, let nsImg = NSImage(data: imgData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - SecurePaste View

    private var securePasteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with back button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        mode = .picker
                        resetSecurePaste()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())

                Text("Secure Paste")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if resultURL == nil {
                // Input mode toggle
                HStack(spacing: 0) {
                    modeTab("Text", icon: "doc.text", selected: inputMode == .text) {
                        inputMode = .text
                    }
                    modeTab("File", icon: "doc", selected: inputMode == .file) {
                        inputMode = .file
                    }
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)

                if inputMode == .text {
                    // Text input
                    TextEditor(text: $securePasteContent)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                        )
                        .padding(.horizontal, 12)
                } else {
                    // File picker button
                    Button {
                        pickFile()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.white.opacity(0.6))
                            Text(securePasteContent.isEmpty ? "Choose File..." : "File loaded (\(securePasteContent.count) chars)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 12)
                }

                // Burn after reading toggle
                Toggle(isOn: $burnAfterReading) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame")
                            .font(.system(size: 10))
                        Text("Burn after reading")
                            .font(.system(.caption, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 12)

                // Create Link button
                Button {
                    Task { await createSecurePaste() }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "link")
                        }
                        Text("Create Link")
                    }
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(securePasteContent.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(securePasteContent.isEmpty || isCreating)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(.caption2))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            } else {
                // Result view
                resultView
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // URL display
            Text(resultURL ?? "")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal, 12)

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    if let url = resultURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy URL")
                    }
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    if let url = resultURL {
                        Task {
                            await quickShare.shareFilesOrText(
                                [url as NSString],
                                using: airdropProvider ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true),
                                from: hostView
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)

            // New paste button
            Button {
                resetSecurePaste()
            } label: {
                Text("Create another")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 10)
        }
    }

    // MARK: - Helpers

    private func modeTab(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select File for Secure Paste"
        panel.allowedContentTypes = [.text, .sourceCode, .json, .xml, .yaml, .plainText, .data]

        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                securePasteContent = content
            } else if let data = try? Data(contentsOf: url) {
                // Binary file — base64 encode
                securePasteContent = data.base64EncodedString()
            }
        }
    }

    @MainActor
    private func createSecurePaste() async {
        guard !securePasteContent.isEmpty else { return }
        isCreating = true
        errorMessage = nil

        do {
            guard let port = await navManager.resolvePort() else {
                errorMessage = "Hub not running"
                isCreating = false
                return
            }

            let url = URL(string: "http://127.0.0.1:\(port)/hub/securebin/create")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "content": securePasteContent,
                "expire": "1week",
                "burn_after_reading": burnAfterReading,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pasteURL = json["url"] as? String,
                   !pasteURL.starts(with: "Error:")
                {
                    withAnimation { resultURL = pasteURL }
                    // Auto-copy
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pasteURL, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } else {
                    errorMessage = "Failed to create paste"
                }
            } else {
                errorMessage = "Server error"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }

    private func resetSecurePaste() {
        securePasteContent = ""
        burnAfterReading = false
        resultURL = nil
        errorMessage = nil
        copied = false
        inputMode = .text
    }
}

// MARK: - Button Style

private struct ShareCardButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { isHovering = $0 }
    }
}

// MARK: - NSView Host (reuse for share sheet anchoring)

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
