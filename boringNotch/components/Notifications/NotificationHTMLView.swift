//
//  NotificationHTMLView.swift
//  boringNotch
//
//  Created by Aitronos on 2026-02-22.
//

import SwiftUI
import WebKit

/// Renders sanitized HTML notification body using a transparent WKWebView.
/// Uses system font at 11px with dark-mode colors to match the Notch aesthetic.
struct NotificationHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = pagePrefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 11px;
                line-height: 1.5;
                color: rgba(255, 255, 255, 0.85);
                background: transparent;
                -webkit-font-smoothing: antialiased;
            }
            p { margin-bottom: 4px; }
            a { color: #3b82f6; text-decoration: underline; }
            strong, b { font-weight: 600; color: rgba(255, 255, 255, 0.95); }
            em, i { font-style: italic; }
            ul, ol { padding-left: 16px; margin: 4px 0; }
            li { margin-bottom: 2px; }
            code {
                font-family: 'SF Mono', Menlo, monospace;
                font-size: 10px;
                padding: 1px 4px;
                border-radius: 3px;
                background: rgba(255, 255, 255, 0.08);
            }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
}
