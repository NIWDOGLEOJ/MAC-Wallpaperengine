//
//  MenuBarController.swift
//  WallpaperEngineCore
//
//  Feature F16: Native macOS Menu Bar status item controller with non-activating menus.
//

import AppKit
import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

// MARK: - Display Menu Item Model

/// Encapsulates display summary data used to render the Displays submenu.
public struct DisplayMenuItemModel: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    public let currentAssetPath: String?
    public let isPaused: Bool

    public init(
        displayID: CGDirectDisplayID,
        name: String,
        frame: CGRect = .zero,
        currentAssetPath: String? = nil,
        isPaused: Bool = false
    ) {
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.currentAssetPath = currentAssetPath
        self.isPaused = isPaused
    }
}

// MARK: - Menu Bar Controller Delegate

@MainActor
public protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidTogglePlayback(_ controller: MenuBarControllerProtocol)
    func menuBar(_ controller: MenuBarControllerProtocol, didSelectAssetURL url: URL, for displayID: CGDirectDisplayID?)
    func menuBar(_ controller: MenuBarControllerProtocol, didUpdateConfig config: EngineConfig)
    func menuBar(_ controller: MenuBarControllerProtocol, didSelectTargetFrameRate fps: Int)
    func menuBar(_ controller: MenuBarControllerProtocol, didTogglePauseFor displayID: CGDirectDisplayID)
    func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderPreset preset: String, for displayID: CGDirectDisplayID?)
    func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderSpeed speed: Float)
    func menuBarDidRequestRevealWallpapers(_ controller: MenuBarControllerProtocol)
    func menuBarDidRequestQuit(_ controller: MenuBarControllerProtocol)
}

extension MenuBarControllerDelegate {
    public func menuBarDidTogglePlayback(_ controller: MenuBarControllerProtocol) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectAssetURL url: URL, for displayID: CGDirectDisplayID?) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didUpdateConfig config: EngineConfig) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectTargetFrameRate fps: Int) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didTogglePauseFor displayID: CGDirectDisplayID) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderPreset preset: String, for displayID: CGDirectDisplayID?) {}
    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderSpeed speed: Float) {}
    public func menuBarDidRequestRevealWallpapers(_ controller: MenuBarControllerProtocol) {}
    public func menuBarDidRequestQuit(_ controller: MenuBarControllerProtocol) {}
}

// MARK: - Status Item Abstractions

@MainActor
public protocol StatusItemButtonProtocol: AnyObject {
    var title: String { get set }
    var toolTip: String? { get set }
    var image: NSImage? { get set }
    var isEnabled: Bool { get set }
}

@MainActor
public protocol StatusItemProtocol: AnyObject {
    var length: CGFloat { get set }
    var menu: NSMenu? { get set }
    var isVisible: Bool { get set }
    var button: (any StatusItemButtonProtocol)? { get }
}

@MainActor
public protocol StatusItemProviderProtocol: AnyObject {
    func makeStatusItem(length: CGFloat) -> any StatusItemProtocol
    func removeStatusItem(_ item: any StatusItemProtocol)
}

public typealias FilePickerHandler = @MainActor (CGDirectDisplayID?, @escaping @MainActor (URL?) -> Void) -> Void

// MARK: - AppKit Concrete Adapters

@MainActor
private final class AppKitStatusItemButtonWrapper: StatusItemButtonProtocol {
    private weak var button: NSStatusBarButton?

    init(button: NSStatusBarButton?) {
        self.button = button
    }

    var title: String {
        get { button?.title ?? "" }
        set { button?.title = newValue }
    }

    var toolTip: String? {
        get { button?.toolTip }
        set { button?.toolTip = newValue }
    }

    var image: NSImage? {
        get { button?.image }
        set { button?.image = newValue }
    }

    var isEnabled: Bool {
        get { button?.isEnabled ?? false }
        set { button?.isEnabled = newValue }
    }
}

@MainActor
public final class AppKitStatusItemWrapper: StatusItemProtocol {
    public let underlyingItem: NSStatusItem
    private let buttonWrapper: AppKitStatusItemButtonWrapper

    public init(underlyingItem: NSStatusItem) {
        self.underlyingItem = underlyingItem
        self.buttonWrapper = AppKitStatusItemButtonWrapper(button: underlyingItem.button)
    }

    public var length: CGFloat {
        get { underlyingItem.length }
        set { underlyingItem.length = newValue }
    }

    public var menu: NSMenu? {
        get { underlyingItem.menu }
        set { underlyingItem.menu = newValue }
    }

    public var isVisible: Bool {
        get { underlyingItem.isVisible }
        set { underlyingItem.isVisible = newValue }
    }

    public var button: (any StatusItemButtonProtocol)? {
        buttonWrapper
    }
}

@MainActor
public final class AppKitStatusItemProvider: StatusItemProviderProtocol {
    public init() {}

    public func makeStatusItem(length: CGFloat) -> any StatusItemProtocol {
        let item = NSStatusBar.system.statusItem(withLength: length)
        return AppKitStatusItemWrapper(underlyingItem: item)
    }

    public func removeStatusItem(_ item: any StatusItemProtocol) {
        if let wrapper = item as? AppKitStatusItemWrapper {
            NSStatusBar.system.removeStatusItem(wrapper.underlyingItem)
        }
    }
}

// MARK: - Menu Bar Controller Protocol

@MainActor
public protocol MenuBarControllerProtocol: AnyObject {
    var delegate: MenuBarControllerDelegate? { get set }
    var isHeadless: Bool { get }
    var isRunning: Bool { get }
    var statusItem: (any StatusItemProtocol)? { get }

    func start()
    func stop()
    func setup()
    func updatePlaybackState(_ state: PlaybackState, decision: PlaybackDecision?, powerInfo: String?)
    func updateStatus(isPlaying: Bool, fps: Int, powerInfo: String)
    func updateDisplays(_ displays: [DisplayMenuItemModel])
    func updateDisplays(displays: [(id: CGDirectDisplayID, name: String, currentAsset: String?)])
    func updateConfig(_ config: EngineConfig)
}

// MARK: - Concrete MenuBarController Implementation

@MainActor
public final class MenuBarController: NSObject, MenuBarControllerProtocol, NSMenuDelegate {
    public weak var delegate: MenuBarControllerDelegate?
    public let isHeadless: Bool
    public private(set) var isRunning: Bool = false
    public private(set) var statusItem: (any StatusItemProtocol)?

    private let statusItemProvider: any StatusItemProviderProtocol
    private let filePickerHandler: FilePickerHandler
    private var currentConfig: EngineConfig
    private var currentDisplays: [DisplayMenuItemModel] = []
    private var isCurrentlyPaused: Bool = false
    private let showTitleInMenuBar: Bool

    // Root menu and cached item references
    private let rootMenu = NSMenu()
    private var statusHeaderItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    private var displaysSubmenu: NSMenu?
    private var preferencesSubmenu: NSMenu?

    // Preference menu item references
    private var pauseOnBatteryItem: NSMenuItem?
    private var pauseOnLPMItem: NSMenuItem?
    private var pauseOnLockItem: NSMenuItem?
    private var pauseOnDisplaySleepItem: NSMenuItem?
    private var pauseWhenOccludedItem: NSMenuItem?
    private var throttleOnBatteryItem: NSMenuItem?
    private var frameRateItems: [Int: NSMenuItem] = [:]

    // Procedural Shader menu item references
    private var shadersSubmenu: NSMenu?
    private var shaderPresetItems: [String: NSMenuItem] = [:]
    private var shaderSpeedItems: [Float: NSMenuItem] = [:]

    // Public accessors for test inspection
    public var rootMenuInstance: NSMenu { rootMenu }
    public var cachedStatusHeaderItem: NSMenuItem? { statusHeaderItem }
    public var cachedPlayPauseItem: NSMenuItem? { playPauseItem }
    public var cachedDisplaysSubmenu: NSMenu? { displaysSubmenu }
    public var cachedPreferencesSubmenu: NSMenu? { preferencesSubmenu }
    public var cachedShadersSubmenu: NSMenu? { shadersSubmenu }

    public init(
        isHeadless: Bool = false,
        config: EngineConfig = EngineConfig(),
        statusItemProvider: (any StatusItemProviderProtocol)? = nil,
        filePickerHandler: FilePickerHandler? = nil,
        showTitleInMenuBar: Bool = true
    ) {
        self.isHeadless = isHeadless
        self.currentConfig = config
        self.showTitleInMenuBar = showTitleInMenuBar
        self.statusItemProvider = statusItemProvider ?? AppKitStatusItemProvider()
        self.filePickerHandler = filePickerHandler ?? { displayID, completion in
            MenuBarController.defaultPresentFilePicker(for: displayID, completion: completion)
        }
        super.init()
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        guard !isHeadless else {
            EngineLogger.menuBar.info("MenuBarController running in headless mode (no NSStatusItem).")
            return
        }

        let item = statusItemProvider.makeStatusItem(length: NSStatusItem.variableLength)
        self.statusItem = item

        // Set button icon
        if let button = item.button {
            let icon = Self.makeStatusIcon()
            button.image = icon
            button.toolTip = "Wallpaper Engine Core"
            if showTitleInMenuBar {
                button.title = "Wallpaper Engine"
            }
        }

        buildRootMenu()
        item.menu = rootMenu
        updateConfig(currentConfig)
    }

    public func setup() {
        start()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let item = statusItem {
            item.menu = nil
            statusItemProvider.removeStatusItem(item)
            self.statusItem = nil
        }
        rootMenu.removeAllItems()
    }

    // MARK: - Icon Generation

    public static func makeStatusIcon() -> NSImage {
        if let primaryIcon = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: "Wallpaper Engine Core") {
            primaryIcon.isTemplate = true
            return primaryIcon
        }
        let fallback = makeFallbackIcon()
        fallback.isTemplate = true
        return fallback
    }

    public static func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext

            // Draw monitor outline
            let monitorRect = CGRect(x: 2, y: 5, width: 14, height: 10)
            let monitorPath = NSBezierPath(roundedRect: monitorRect, xRadius: 1.5, yRadius: 1.5)
            monitorPath.lineWidth = 1.2
            NSColor.black.setStroke()
            monitorPath.stroke()

            // Draw monitor stand
            let standPath = NSBezierPath()
            standPath.move(to: NSPoint(x: 9, y: 5))
            standPath.line(to: NSPoint(x: 9, y: 2))
            standPath.move(to: NSPoint(x: 6, y: 2))
            standPath.line(to: NSPoint(x: 12, y: 2))
            standPath.lineWidth = 1.2
            standPath.stroke()

            // Draw play triangle inside monitor
            let playPath = NSBezierPath()
            playPath.move(to: NSPoint(x: 7.5, y: 12.5))
            playPath.line(to: NSPoint(x: 11.5, y: 10))
            playPath.line(to: NSPoint(x: 7.5, y: 7.5))
            playPath.close()
            NSColor.black.setFill()
            playPath.fill()

            _ = context
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Menu Construction

    private func buildRootMenu() {
        rootMenu.removeAllItems()
        rootMenu.autoenablesItems = false

        // 1. Status Header (Item 0)
        let header = NSMenuItem(title: "◉ Status: Initializing...", action: nil, keyEquivalent: "")
        header.isEnabled = false
        rootMenu.addItem(header)
        self.statusHeaderItem = header

        // 2. Play / Pause Toggle (Item 1)
        let toggle = NSMenuItem(title: "Pause Playback", action: #selector(handlePlayPauseClicked(_:)), keyEquivalent: "p")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        rootMenu.addItem(toggle)
        self.playPauseItem = toggle

        rootMenu.addItem(.separator())

        // 3. Displays Submenu (Item 3)
        let displaysMenu = NSMenu(title: "Displays")
        displaysMenu.autoenablesItems = false
        let displaysParentItem = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        displaysParentItem.submenu = displaysMenu
        rootMenu.addItem(displaysParentItem)
        self.displaysSubmenu = displaysMenu
        rebuildDisplaysSubmenu()

        rootMenu.addItem(.separator())

        // 4. Procedural Shaders Submenu
        let shadersMenu = NSMenu(title: "Procedural Shaders")
        shadersMenu.autoenablesItems = false
        buildProceduralShadersSubmenu(shadersMenu)
        let shadersParentItem = NSMenuItem(title: "Procedural Shaders", action: nil, keyEquivalent: "")
        shadersParentItem.submenu = shadersMenu
        rootMenu.addItem(shadersParentItem)
        self.shadersSubmenu = shadersMenu

        rootMenu.addItem(.separator())

        // 5. Preferences Submenu
        let prefMenu = NSMenu(title: "Preferences")
        prefMenu.autoenablesItems = false
        buildPreferencesSubmenu(prefMenu)
        let prefParentItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefParentItem.submenu = prefMenu
        rootMenu.addItem(prefParentItem)
        self.preferencesSubmenu = prefMenu

        rootMenu.addItem(.separator())

        // 5. Reveal Wallpapers in Finder
        let revealItem = NSMenuItem(title: "Reveal Wallpapers in Finder", action: #selector(handleRevealWallpapersClicked(_:)), keyEquivalent: "")
        revealItem.target = self
        rootMenu.addItem(revealItem)

        rootMenu.addItem(.separator())

        // 6. Quit Item
        let quitItem = NSMenuItem(title: "Quit Wallpaper Engine Core", action: #selector(handleQuitClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        rootMenu.addItem(quitItem)
    }

    private func rebuildDisplaysSubmenu() {
        guard let submenu = displaysSubmenu else { return }
        submenu.removeAllItems()

        if currentDisplays.isEmpty {
            let emptyItem = NSMenuItem(title: "No Displays Connected", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        for (index, display) in currentDisplays.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }

            let titleItem = NSMenuItem(title: "\(display.name) (\(Int(display.frame.width))×\(Int(display.frame.height)))", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            submenu.addItem(titleItem)

            let assetName = display.currentAssetPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "None"
            let assetItem = NSMenuItem(title: "  Current: \(assetName)", action: nil, keyEquivalent: "")
            assetItem.isEnabled = false
            submenu.addItem(assetItem)

            let chooseItem = NSMenuItem(title: "  Choose Wallpaper...", action: #selector(handleChooseWallpaperClicked(_:)), keyEquivalent: "")
            chooseItem.target = self
            chooseItem.representedObject = display.displayID
            submenu.addItem(chooseItem)

            let pauseTitle = display.isPaused ? "  Resume This Screen" : "  Pause This Screen"
            let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(handleToggleDisplayPauseClicked(_:)), keyEquivalent: "")
            pauseItem.target = self
            pauseItem.representedObject = display.displayID
            submenu.addItem(pauseItem)
        }

        submenu.addItem(.separator())

        let chooseAllItem = NSMenuItem(title: "Assign Wallpaper to All Displays...", action: #selector(handleChooseWallpaperForAllClicked(_:)), keyEquivalent: "")
        chooseAllItem.target = self
        submenu.addItem(chooseAllItem)
    }

    private func buildProceduralShadersSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        shaderPresetItems.removeAll()
        shaderSpeedItems.removeAll()

        for preset in ProceduralShaderPreset.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(handleSelectShaderPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            menu.addItem(item)
            shaderPresetItems[preset.rawValue] = item
        }

        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "Import Custom Shader...", action: #selector(handleImportCustomShaderClicked(_:)), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())

        let speedMenu = NSMenu(title: "Shader Speed")
        speedMenu.autoenablesItems = false
        let speeds: [(Float, String)] = [
            (0.5, "0.5x (Slow)"),
            (1.0, "1.0x (Normal)"),
            (1.5, "1.5x (Fast)"),
            (2.0, "2.0x (Ultra)")
        ]
        for (sp, label) in speeds {
            let spItem = NSMenuItem(title: label, action: #selector(handleSelectShaderSpeed(_:)), keyEquivalent: "")
            spItem.target = self
            spItem.representedObject = sp
            speedMenu.addItem(spItem)
            shaderSpeedItems[sp] = spItem
        }
        let speedParent = NSMenuItem(title: "Shader Speed", action: nil, keyEquivalent: "")
        speedParent.submenu = speedMenu
        menu.addItem(speedParent)
    }

    private func buildPreferencesSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        func addCheckbox(title: String, selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }

        pauseOnBatteryItem = addCheckbox(title: "Pause on Battery", selector: #selector(handleTogglePauseOnBattery(_:)))
        pauseOnLPMItem = addCheckbox(title: "Pause on Low Power Mode", selector: #selector(handleTogglePauseOnLPM(_:)))
        pauseOnLockItem = addCheckbox(title: "Pause on Screen Lock", selector: #selector(handleTogglePauseOnLock(_:)))
        pauseOnDisplaySleepItem = addCheckbox(title: "Pause on Display Sleep", selector: #selector(handleTogglePauseOnDisplaySleep(_:)))
        pauseWhenOccludedItem = addCheckbox(title: "Pause When Occluded", selector: #selector(handleTogglePauseWhenOccluded(_:)))
        throttleOnBatteryItem = addCheckbox(title: "Throttle on Battery", selector: #selector(handleToggleThrottleOnBattery(_:)))

        menu.addItem(.separator())

        // Target Frame Rate Submenu
        let fpsMenu = NSMenu(title: "Target Frame Rate")
        fpsMenu.autoenablesItems = false
        frameRateItems.removeAll()

        let rates: [(fps: Int, label: String)] = [
            (30, "30 FPS (Power Saver)"),
            (60, "60 FPS (Standard)"),
            (120, "120 FPS (ProMotion)"),
            (144, "144 FPS (High Refresh)"),
            (240, "240 FPS (Ultra High Refresh)")
        ]

        for entry in rates {
            let item = NSMenuItem(title: entry.label, action: #selector(handleSelectFrameRate(_:)), keyEquivalent: "")
            item.target = self
            item.tag = entry.fps
            fpsMenu.addItem(item)
            frameRateItems[entry.fps] = item
        }

        let fpsParent = NSMenuItem(title: "Target Frame Rate", action: nil, keyEquivalent: "")
        fpsParent.submenu = fpsMenu
        menu.addItem(fpsParent)
    }

    // MARK: - State Updates

    public func updatePlaybackState(_ state: PlaybackState, decision: PlaybackDecision?, powerInfo: String?) {
        let (statusText, isPaused): (String, Bool) = {
            switch state {
            case .playing:
                let fps = currentConfig.targetFrameRate
                return ("Playing (\(fps) FPS)", false)
            case .paused(let reason):
                return ("Paused (\(reason.rawValue))", true)
            case .throttled(let fps):
                return ("Throttled (\(fps) FPS)", false)
            case .loading(let url):
                return ("Loading (\(url.lastPathComponent))...", false)
            case .stalled(let reason):
                return ("Stalled (\(reason))", true)
            case .failed(let err):
                return ("Error: \(err.localizedDescription)", true)
            case .idle:
                return ("Idle", true)
            }
        }()

        self.isCurrentlyPaused = isPaused

        let powerSuffix = powerInfo.map { " • \($0)" } ?? ""
        let fullStatus = "◉ Status: \(statusText)\(powerSuffix)"
        statusHeaderItem?.title = fullStatus

        playPauseItem?.title = isPaused ? "Resume Playback" : "Pause Playback"

        if let button = statusItem?.button {
            button.toolTip = "Wallpaper Engine Core: \(statusText)\(powerSuffix)"
            if showTitleInMenuBar {
                if isPaused {
                    button.title = "Paused"
                } else if case .throttled(let fps) = state {
                    button.title = "Throttled (\(fps) FPS)"
                } else {
                    button.title = "Playing (\(currentConfig.targetFrameRate) FPS)"
                }
            }
        }
    }

    public func updateStatus(isPlaying: Bool, fps: Int, powerInfo: String) {
        let state: PlaybackState = isPlaying ? (fps < currentConfig.targetFrameRate ? .throttled(fps: fps) : .playing) : .paused(reason: .userRequested)
        updatePlaybackState(state, decision: nil, powerInfo: powerInfo)
    }

    public func updateDisplays(_ displays: [DisplayMenuItemModel]) {
        self.currentDisplays = displays
        rebuildDisplaysSubmenu()
    }

    public func updateDisplays(displays: [(id: CGDirectDisplayID, name: String, currentAsset: String?)]) {
        let models = displays.map { d in
            DisplayMenuItemModel(
                displayID: d.id,
                name: d.name,
                frame: .zero,
                currentAssetPath: d.currentAsset,
                isPaused: false
            )
        }
        updateDisplays(models)
    }

    public func updateConfig(_ config: EngineConfig) {
        self.currentConfig = config

        pauseOnBatteryItem?.state = config.pauseOnBattery ? .on : .off
        pauseOnLPMItem?.state = config.pauseOnLowPowerMode ? .on : .off
        pauseOnLockItem?.state = config.pauseOnScreenLock ? .on : .off
        pauseOnDisplaySleepItem?.state = config.pauseOnDisplaySleep ? .on : .off
        pauseWhenOccludedItem?.state = config.pauseWhenOccluded ? .on : .off
        throttleOnBatteryItem?.state = config.throttleOnBattery ? .on : .off

        for (fps, item) in frameRateItems {
            item.state = (config.targetFrameRate == fps) ? .on : .off
        }

        for (name, item) in shaderPresetItems {
            item.state = (config.shaderName == name) ? .on : .off
        }

        for (sp, item) in shaderSpeedItems {
            item.state = (abs(config.shaderSpeed - sp) < 0.05) ? .on : .off
        }
    }

    // MARK: - Action Handlers

    @objc public func handlePlayPauseClicked(_ sender: Any?) {
        delegate?.menuBarDidTogglePlayback(self)
    }

    @objc public func handleChooseWallpaperClicked(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else { return }
        filePickerHandler(displayID) { [weak self] url in
            guard let self = self, let selectedURL = url else { return }
            self.delegate?.menuBar(self, didSelectAssetURL: selectedURL, for: displayID)
        }
    }

    @objc public func handleChooseWallpaperForAllClicked(_ sender: Any?) {
        filePickerHandler(nil) { [weak self] url in
            guard let self = self, let selectedURL = url else { return }
            self.delegate?.menuBar(self, didSelectAssetURL: selectedURL, for: nil)
        }
    }

    @objc public func handleSelectShaderPreset(_ sender: NSMenuItem) {
        guard let rawVal = sender.representedObject as? String else { return }
        currentConfig.shaderName = rawVal
        currentConfig.shaderPath = nil
        updateConfig(currentConfig)
        delegate?.menuBar(self, didSelectShaderPreset: rawVal, for: nil)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleImportCustomShaderClicked(_ sender: Any?) {
        filePickerHandler(nil) { [weak self] url in
            guard let self = self, let selectedURL = url else { return }
            self.currentConfig.shaderName = nil
            self.currentConfig.shaderPath = selectedURL.path
            self.updateConfig(self.currentConfig)
            self.delegate?.menuBar(self, didSelectAssetURL: selectedURL, for: nil)
            self.delegate?.menuBar(self, didUpdateConfig: self.currentConfig)
        }
    }

    @objc public func handleSelectShaderSpeed(_ sender: NSMenuItem) {
        guard let sp = sender.representedObject as? Float else { return }
        currentConfig.shaderSpeed = sp
        updateConfig(currentConfig)
        delegate?.menuBar(self, didSelectShaderSpeed: sp)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleToggleDisplayPauseClicked(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else { return }
        delegate?.menuBar(self, didTogglePauseFor: displayID)
    }

    @objc public func handleTogglePauseOnBattery(_ sender: Any?) {
        currentConfig.pauseOnBattery.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleTogglePauseOnLPM(_ sender: Any?) {
        currentConfig.pauseOnLowPowerMode.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleTogglePauseOnLock(_ sender: Any?) {
        currentConfig.pauseOnScreenLock.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleTogglePauseOnDisplaySleep(_ sender: Any?) {
        currentConfig.pauseOnDisplaySleep.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleTogglePauseWhenOccluded(_ sender: Any?) {
        currentConfig.pauseWhenOccluded.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleToggleThrottleOnBattery(_ sender: Any?) {
        currentConfig.throttleOnBattery.toggle()
        updateConfig(currentConfig)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleSelectFrameRate(_ sender: NSMenuItem) {
        let fps = sender.tag
        currentConfig.targetFrameRate = fps
        updateConfig(currentConfig)
        delegate?.menuBar(self, didSelectTargetFrameRate: fps)
        delegate?.menuBar(self, didUpdateConfig: currentConfig)
    }

    @objc public func handleRevealWallpapersClicked(_ sender: Any?) {
        delegate?.menuBarDidRequestRevealWallpapers(self)
    }

    @objc public func handleQuitClicked(_ sender: Any?) {
        delegate?.menuBarDidRequestQuit(self)
    }

    // MARK: - File Picker Presentation Helper

    public static func defaultPresentFilePicker(for displayID: CGDirectDisplayID?, completion: @escaping @MainActor (URL?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = .modalPanel
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .image, .jpeg, .png, .heic, .sourceCode, .plainText, .text]
        panel.title = (displayID != nil) ? "Choose Wallpaper (Video, 3D Photo, or Shader) for Display \(displayID!)" : "Choose Wallpaper (Video, 3D Photo, or Shader) for All Displays"
        panel.prompt = "Set Wallpaper"

        let response = panel.runModal()
        if response == .OK {
            completion(panel.url)
        } else {
            completion(nil)
        }
    }
}
