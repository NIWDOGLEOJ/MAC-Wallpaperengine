//
//  WebWallpaperView.swift
//  WallpaperEngineCore
//
//  Feature 4.E: Sandboxed, resource-efficient HTML5/CSS/JavaScript Web Wallpaper.
//  Uses WKWebView with strict sandboxing, lifecycle suspension, and security controls.
//

import AppKit
import Foundation
import OSLog
import WebKit

@MainActor
public final class WebWallpaperView: NSView, WKNavigationDelegate, WKUIDelegate {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "WebWallpaperView")
    public private(set) var webView: WKWebView?
    public private(set) var currentURL: URL?
    public private(set) var isPaused: Bool = false
    public var allowNetworkRequests: Bool = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupContainer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContainer()
    }

    private func setupContainer() {
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    public func loadWebWallpaper(from htmlURL: URL, allowNetwork: Bool = false) {
        self.currentURL = htmlURL
        self.allowNetworkRequests = allowNetwork

        // Teardown existing web view if any
        teardownWebView()

        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // Security restrictions
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        if !allowNetwork {
            // Defense-in-depth: Inject CSP meta tag to prevent outbound fetches/connections
            let cspSource = "const meta = document.createElement('meta'); meta.httpEquiv = 'Content-Security-Policy'; meta.content = \"default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: file:;\"; document.head.appendChild(meta);"
            let userScript = WKUserScript(source: cspSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(userScript)
        }

        let wv = WKWebView(frame: bounds, configuration: configuration)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.setValue(false, forKey: "drawsBackground") // Transparent background support

        addSubview(wv)
        self.webView = wv

        // Safe file URL access: only allow read access to the directory containing the HTML file
        let directoryURL = htmlURL.deletingLastPathComponent()
        wv.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
        logger.info("Loaded web wallpaper from \(htmlURL.lastPathComponent)")
    }

    public func pause() {
        guard !isPaused, let wv = webView else { return }
        isPaused = true
        wv.setAllMediaPlaybackSuspended(true)
        // Notify wallpaper of suspension and throttle JS execution
        wv.evaluateJavaScript("if (window.__wallpaperPause) { window.__wallpaperPause(); } else if (window.cancelAnimationFrame) { /* suspended */ }") { _, _ in }
        wv.evaluateJavaScript("document.body.style.animationPlayState = 'paused';") { _, _ in }
        wv.isHidden = false // Keep last frame visible without continuing to redraw
        logger.info("Web wallpaper paused.")
    }

    public func resume() {
        guard isPaused, let wv = webView else { return }
        isPaused = false
        wv.setAllMediaPlaybackSuspended(false)
        wv.evaluateJavaScript("if (window.__wallpaperResume) { window.__wallpaperResume(); }") { _, _ in }
        wv.evaluateJavaScript("document.body.style.animationPlayState = 'running';") { _, _ in }
        logger.info("Web wallpaper resumed.")
    }

    public func teardownWebView() {
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.removeFromSuperview()
            webView = nil
        }
        isPaused = false
    }
}

// MARK: - WKNavigationDelegate Security Enforcement

extension WebWallpaperView {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow initial file loading
        if url.isFileURL {
            if let root = currentURL?.deletingLastPathComponent(), url.path.hasPrefix(root.path) {
                decisionHandler(.allow)
                return
            }
        }

        // Restrict arbitrary network navigation unless explicitly enabled
        if (url.scheme == "http" || url.scheme == "https") && allowNetworkRequests {
            decisionHandler(.allow)
            return
        }

        logger.warning("Blocked untrusted navigation to \(url.absoluteString)")
        decisionHandler(.cancel)
    }
}

