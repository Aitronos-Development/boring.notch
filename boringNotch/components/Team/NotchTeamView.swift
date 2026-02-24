//
//  NotchTeamView.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-17.
//

import Defaults
import SwiftUI

@MainActor
struct NotchTeamView: View {
    @ObservedObject var teamManager = TeamPresenceManager.shared
    @Default(.secureBinDefaultEnabled) var secureBinDefaultEnabled
    @Default(.secureBinExpire) var secureBinExpire
    @Default(.secureBinBurnAfterReading) var secureBinBurnAfterReading
    @Default(.secureBinRequirePassword) var secureBinRequirePassword
    @State private var activeChat: TeamMember?
    @State private var messageText: String = ""
    @State private var secureBinEnabled: Bool = false
    @State private var attachmentPath: String?
    @State private var isSending: Bool = false
    @State private var sendError: String?
    @State private var noAppleIdMember: TeamMember?
    @State private var sentPassword: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Team")
                    .font(.headline)
                    .foregroundStyle(.white)

                if teamManager.isLoaded && Defaults[.showTeamOnlineCount] {
                    Text("\(teamManager.onlineCount) online")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()

                // Current user status selector
                NotchStatusSelector()
            }

            Divider()
                .background(Color.gray.opacity(0.3))

            // Content area
            if teamManager.members.isEmpty && !teamManager.isLoaded {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading team...")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if teamManager.members.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.title2)
                        .foregroundStyle(.gray)
                    Text("No team members found")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(teamManager.members) { member in
                            TeamMemberRow(
                                member: member,
                                onMessage: { startChat(with: member) },
                                onNoAppleId: { noAppleIdMember = member },
                                onFaceTime: {
                                    if let appleId = member.appleId, !appleId.isEmpty {
                                        teamManager.openFaceTime(to: appleId)
                                    }
                                },
                                onFaceTimeAudio: {
                                    if let appleId = member.appleId, !appleId.isEmpty {
                                        teamManager.openFaceTimeAudio(to: appleId)
                                    }
                                },
                                onEmail: { teamManager.openEmail(to: member.email) },
                                onDownloadContact: { teamManager.downloadContact(member) }
                            )
                        }
                    }
                }
            }

            // Inline message input bar
            if let chat = activeChat {
                MessageInputBar(
                    recipient: chat,
                    messageText: $messageText,
                    secureBinEnabled: $secureBinEnabled,
                    attachmentPath: $attachmentPath,
                    isSending: isSending,
                    sendError: sendError,
                    onSend: { sendMessage(to: chat) },
                    onAttach: { pickFile() },
                    onDismiss: { dismissChat() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Password banner (shown after sending an encrypted message with password)
            if let password = sentPassword {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Password:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                    Text(password)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(password, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Copy password")
                    Button(action: { sentPassword = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // No Apple ID warning
            if let member = noAppleIdMember {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("\(member.name) does not have a valid Apple ID configured.")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    Spacer()
                    Button(action: { noAppleIdMember = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activeChat?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: noAppleIdMember?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sentPassword)
        .onDisappear {
            if activeChat != nil {
                requestKeyboardInput(false)
            }
        }
    }

    private func startChat(with member: TeamMember) {
        guard let appleId = member.appleId, !appleId.isEmpty else { return }
        activeChat = member
        messageText = ""
        secureBinEnabled = secureBinDefaultEnabled
        attachmentPath = nil
        sendError = nil
        sentPassword = nil
        requestKeyboardInput(true)
    }

    private func dismissChat() {
        requestKeyboardInput(false)
        activeChat = nil
        messageText = ""
        attachmentPath = nil
        sendError = nil
        sentPassword = nil
    }

    private func requestKeyboardInput(_ enabled: Bool) {
        NotificationCenter.default.post(
            name: BoringNotchSkyLightWindow.keyboardInputNotification,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    private func sendMessage(to member: TeamMember) {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentPath != nil else { return }
        isSending = true
        sendError = nil
        sentPassword = nil

        // Generate a random password if required
        let password: String? = (secureBinEnabled && secureBinRequirePassword)
            ? generatePassword()
            : nil

        Task {
            let result = await teamManager.sendMessage(
                to: member,
                text: messageText,
                secureBin: secureBinEnabled,
                attachmentPath: attachmentPath,
                expire: secureBinExpire,
                burnAfterReading: secureBinBurnAfterReading,
                password: password
            )
            isSending = false
            if result.success {
                messageText = ""
                attachmentPath = nil
                // Show password to sender so they can share it separately
                if let pw = result.secureBinPassword {
                    sentPassword = pw
                }
            } else {
                sendError = "Failed to send"
            }
        }
    }

    /// Generate a random 16-character alphanumeric password
    private func generatePassword() -> String {
        let chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                attachmentPath = url.path
            }
        }
    }
}

// MARK: - Message Input Bar

private struct MessageInputBar: View {
    let recipient: TeamMember
    @Binding var messageText: String
    @Binding var secureBinEnabled: Bool
    @Binding var attachmentPath: String?
    let isSending: Bool
    let sendError: String?
    let onSend: () -> Void
    let onAttach: () -> Void
    let onDismiss: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    /// Approximate line count for dynamic height
    private var lineCount: Int {
        let newlines = messageText.components(separatedBy: "\n").count
        // Also account for line wrapping (~40 chars per line at font size 11)
        let wrappedLines = messageText.components(separatedBy: "\n").reduce(0) { total, line in
            total + max(1, Int(ceil(Double(line.count) / 40.0)))
        }
        return max(newlines, wrappedLines)
    }

    /// Dynamic height: single line = 20pt, grows up to 5 visible lines
    private var editorHeight: CGFloat {
        let singleLineHeight: CGFloat = 20
        let lineHeight: CGFloat = 15
        let clamped = min(max(lineCount, 1), 5)
        return singleLineHeight + lineHeight * CGFloat(clamped - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Recipient bar with dismiss button
            HStack(spacing: 6) {
                Text("To:")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Text(recipient.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }

            // Attachment chip
            if let path = attachmentPath {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 9))
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 9))
                        .lineLimit(1)
                    Button(action: { attachmentPath = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .foregroundStyle(.gray)
            }

            // Input area
            HStack(alignment: .bottom, spacing: 6) {
                // Left toolbar buttons (vertically centered with text area)
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    // Attachment button
                    Button(action: onAttach) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)

                    // SecureBin toggle
                    Button(action: { secureBinEnabled.toggle() }) {
                        Image(systemName: secureBinEnabled ? "lock.fill" : "lock.open")
                            .font(.system(size: 11))
                            .foregroundStyle(secureBinEnabled ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                    .help(secureBinEnabled ? "SecureBin: ON" : "SecureBin: OFF")
                }
                .frame(height: editorHeight)

                // Multi-line text editor
                MultiLineTextField(
                    text: $messageText,
                    isFocused: $isTextFieldFocused,
                    onSubmit: onSend
                )
                .frame(height: editorHeight)

                // Send button (pinned to bottom)
                VStack {
                    Spacer(minLength: 0)
                    Button(action: onSend) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || isSending)
                }
                .frame(height: editorHeight)
            }

            // Hint for multi-line
            if lineCount <= 1 {
                Text("⏎ Send  ⌥⏎ New line")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray.opacity(0.5))
            }

            // Error message
            if let error = sendError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentPath != nil
    }
}

// MARK: - Multi-line Text Field (NSTextView wrapper)

/// A multi-line text input that uses NSTextView under the hood.
/// - Enter sends the message
/// - Option+Enter or Shift+Enter inserts a newline
/// - Supports standard undo/redo (Cmd+Z / Cmd+Shift+Z), select all, cut/copy/paste
private struct MultiLineTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = SendableTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        // Remove default padding so text aligns with the rest of the bar
        textView.textContainerInset = NSSize(width: 0, height: 2)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        // Focus handling
        if isFocused.wrappedValue, textView.window != nil, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultiLineTextField
        weak var textView: NSTextView?

        init(_ parent: MultiLineTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// NSTextView subclass that intercepts Enter to send and Option/Shift+Enter for newlines.
private class SendableTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let hasOption = event.modifierFlags.contains(.option)
        let hasShift = event.modifierFlags.contains(.shift)

        if isReturn && !hasOption && !hasShift {
            // Plain Enter → send
            onSubmit?()
            return
        }

        if isReturn && (hasOption || hasShift) {
            // Option+Enter or Shift+Enter → insert newline
            insertNewline(nil)
            return
        }

        super.keyDown(with: event)
    }

    /// Show placeholder when empty
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty {
            let placeholder = "Message..."
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.gray
            ]
            let inset = textContainerInset
            let rect = NSRect(
                x: inset.width + 5,
                y: inset.height,
                width: bounds.width - inset.width * 2 - 5,
                height: bounds.height - inset.height * 2
            )
            placeholder.draw(in: rect, withAttributes: attrs)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }
}

// MARK: - Team Member Row

private struct TeamMemberRow: View {
    let member: TeamMember
    let onMessage: () -> Void
    let onNoAppleId: () -> Void
    let onFaceTime: () -> Void
    let onFaceTimeAudio: () -> Void
    let onEmail: () -> Void
    let onDownloadContact: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Avatar with status dot
            ZStack(alignment: .bottomTrailing) {
                if let picture = member.picture, let url = URL(string: picture) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        initialsAvatar
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                } else {
                    initialsAvatar
                }

                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)
            }

            // Name and status
            VStack(alignment: .leading, spacing: 0) {
                Text(member.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let statusText = member.statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons (visible on hover) or status badge
            if isHovered {
                HStack(spacing: 4) {
                    if hasAppleId {
                        ActionButton(icon: "message.fill", color: .blue, action: onMessage)
                            .help("Send iMessage")
                        ActionButton(icon: "video.fill", color: .green, action: onFaceTime)
                            .help("FaceTime Video")
                    } else {
                        ActionButton(icon: "message.fill", color: .gray.opacity(0.3), action: onNoAppleId)
                            .help("No Apple ID configured")
                    }
                    ActionButton(icon: "envelope.fill", color: .orange, action: onEmail)
                        .help("Send email")
                    Menu {
                        if hasAppleId {
                            Button(action: onFaceTimeAudio) {
                                Label("FaceTime Audio", systemImage: "phone.fill")
                            }
                            Divider()
                        }
                        Button(action: onDownloadContact) {
                            Label("Download Contact", systemImage: "person.crop.circle.badge.plus")
                        }
                        Button(action: { NSPasteboard.general.setString(member.email, forType: .string) }) {
                            Label("Copy Email", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                }
                .transition(.opacity)
            } else {
                Text(member.presenceStatus.label)
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var hasAppleId: Bool {
        member.appleId != nil && !(member.appleId?.isEmpty ?? true)
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 24, height: 24)
            .overlay(
                Text(initials)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let parts = member.name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }

    private var statusColor: Color {
        switch member.presenceStatus.dotColor {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(color.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
