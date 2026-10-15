//
//  DesktopWindow.swift
//  WallpaperEngineCore
//
//  Borderless, non-activating desktop window anchored beneath desktop icons.
//

import AppKit
import CoreGraphics
import QuartzCore

// MARK: - Desktop Window Protocol

/// Interface defining the behavior and lifecycle of a desktop wallpaper window.
@MainActor
public protocol DesktopWindowProtocol: AnyObject {
    /// Physical display identifier this window is bound to.
    var displayID: CGDirectDisplayID { get }

    /// The underlying AppKit NSWindow instance.
    var underlyingWindow: NSWindow { get }

    /// The root layer-backed hosting layer of the window's content view.
    var rootHostingLayer: CALayer? { get }

    /// Alias for rootHostingLayer matching test harness contracts.
    var contentLayer: CALayer? { get set }

    /// The currently active player layer rendering video.
    var currentActiveLayer: CALayer? { get }

    /// Whether the window is currently ordered on screen.
    var isVisible: Bool { get }

    /// The current window frame geometry.
    var frame: CGRect { get }

    /// Integer raw value of the window level.
    var windowLevel: Int { get }

    /// Collection behavior flags currently assigned to the window.
    var collectionBehaviorFlags: NSWindow.CollectionBehavior { get }

    /// Whether mouse events are ignored by WindowServer hit-testing.
    var ignoresMouseEventsFlag: Bool { get }

    /// Whether the window can become the key window.
    var canBecomeKey: Bool { get }

    /// Whether the window can become the main document window.
    var canBecomeMain: Bool { get }

    /// Attaches a player layer immediately, replacing any existing video layer.
    func attachPlayerLayer(_ playerLayer: CALayer)

    /// Detaches and removes the current video player layer.
    func removePlayerLayer()

    /// Smoothly crossfades from the current video layer to a new player layer.
    func transitionToPlayerLayer(_ newLayer: CALayer, duration: TimeInterval)

    /// Updates the window and sublayer geometry to match updated screen bounds.
    func updateFrame(_ newFrame: CGRect)

    /// Orders the window to its designated desktop level beneath icons.
    func orderToDesktopLevel()

    /// Closes the window and thoroughly purges all layer and view references.
    func closeAndRelease()
}

extension DesktopWindowProtocol {
    public var canBecomeKeyWindow: Bool { canBecomeKey }
    public var canBecomeMainWindow: Bool { canBecomeMain }
}

// MARK: - Concrete DesktopWindow Implementation

/// Custom NSWindow anchored strictly beneath Finder desktop icons at kCGDesktopWindowLevelKey.
@MainActor
public final class DesktopWindow: NSWindow, DesktopWindowProtocol {
    public let displayID: CGDirectDisplayID

    private let videoContainerLayer = CALayer()
    private var activePlayerLayer: CALayer?

    public var underlyingWindow: NSWindow { self }

    public var rootHostingLayer: CALayer? {
        contentView?.layer
    }

    public var contentLayer: CALayer? {
        get { rootHostingLayer }
        set {
            if let newLayer = newValue {
                attachPlayerLayer(newLayer)
            } else {
                removePlayerLayer()
            }
        }
    }

    public var currentActiveLayer: CALayer? {
        activePlayerLayer
    }

    public var windowLevel: Int {
        level.rawValue
    }

    public var collectionBehaviorFlags: NSWindow.CollectionBehavior {
        collectionBehavior
    }

    public var ignoresMouseEventsFlag: Bool {
        ignoresMouseEvents
    }

    // MARK: - Initializers

    /// Designated initializer accepting content rectangle and display ID.
    public init(contentRect: CGRect, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindowLevel()
        configureCollectionBehaviors()
        configureEventPassThrough()
        configureVisualProperties()
        setupLayerHierarchy(frame: contentRect)
    }

    /// Convenience initializer using frame geometry.
    public convenience init(frame: CGRect, displayID: CGDirectDisplayID) {
        self.init(contentRect: frame, displayID: displayID)
    }

    /// Convenience initializer using an AppKit NSScreen instance.
    public convenience init(screen: NSScreen, displayID: CGDirectDisplayID? = nil) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let resolvedID = displayID
            ?? (screen.deviceDescription[key] as? NSNumber)?.uint32Value
            ?? (screen.deviceDescription[key] as? CGDirectDisplayID)
            ?? 0
        self.init(contentRect: screen.frame, displayID: resolvedID)
    }

    /// Convenience initializer using a ScreenDescriptor.
    public convenience init(screen: ScreenDescriptor) {
        self.init(contentRect: screen.frame, displayID: screen.displayID)
    }

    // MARK: - Window Configuration

    private func configureWindowLevel() {
        // Places window at -2147483623 (kCGDesktopWindowLevelKey), exactly 20 levels beneath Finder desktop icons (-2147483603)
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    }

    private func configureCollectionBehaviors() {
        // Pins window across virtual desktops, excludes from Mission Control, Exposé, and Cmd+Tab cycling
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
    }

    private func configureEventPassThrough() {
        // WindowServer hit-testing completely bypasses this window; user clicks fall directly to Finder
        self.ignoresMouseEvents = true
    }

    private func configureVisualProperties() {
        self.hasShadow = false
        self.isOpaque = true
        self.backgroundColor = .black
        self.canHide = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.isReleasedWhenClosed = false
        self.sharingType = .none
        self.displaysWhenScreenProfileChanges = true
    }

    private func setupLayerHierarchy(frame: CGRect) {
        let hostingView = NSView(frame: frame)
        hostingView.wantsLayer = true

        if let root = hostingView.layer {
            root.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            videoContainerLayer.frame = root.bounds
            videoContainerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            root.addSublayer(videoContainerLayer)
        }

        self.contentView = hostingView
    }

    // MARK: - Non-Activating Focus Overrides

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    // MARK: - Layer Attachment & Video Transitions

    public func attachPlayerLayer(_ playerLayer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        activePlayerLayer?.removeFromSuperlayer()
        playerLayer.frame = videoContainerLayer.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoContainerLayer.addSublayer(playerLayer)
        activePlayerLayer = playerLayer

        CATransaction.commit()
    }

    public func removePlayerLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activePlayerLayer?.removeFromSuperlayer()
        activePlayerLayer = nil
        CATransaction.commit()
    }

    public func transitionToPlayerLayer(_ newLayer: CALayer, duration: TimeInterval = 0.5) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        newLayer.frame = videoContainerLayer.bounds
        newLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        newLayer.opacity = 0.0
        videoContainerLayer.addSublayer(newLayer)

        CATransaction.commit()

        let oldLayer = activePlayerLayer
        activePlayerLayer = newLayer

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setCompletionBlock {
            oldLayer?.removeFromSuperlayer()
        }

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = duration
        newLayer.add(fadeIn, forKey: "fadeTransition")
        newLayer.opacity = 1.0

        if let old = oldLayer {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = duration
            old.add(fadeOut, forKey: "fadeTransitionOut")
            old.opacity = 0.0
        }

        CATransaction.commit()
    }

    // MARK: - Geometry & Window Lifecycle

    public func updateFrame(_ newFrame: CGRect) {
        guard self.frame != newFrame else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.setFrame(newFrame, display: true, animate: false)
        if let contentView = self.contentView {
            contentView.frame = CGRect(origin: .zero, size: newFrame.size)
            videoContainerLayer.frame = contentView.bounds
            activePlayerLayer?.frame = videoContainerLayer.bounds
        }

        CATransaction.commit()
    }

    public func orderToDesktopLevel() {
        self.orderFrontRegardless()
    }

    private var isClosed = false

    public func closeAndRelease() {
        guard !isClosed else { return }
        isClosed = true
        self.orderOut(nil)
        removePlayerLayer()
        videoContainerLayer.removeFromSuperlayer()
        self.contentView = nil
        self.isReleasedWhenClosed = true
        _ = Unmanaged.passRetained(self)
        self.close()
    }
}
