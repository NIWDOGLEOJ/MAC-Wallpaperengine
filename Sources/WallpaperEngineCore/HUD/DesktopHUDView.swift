//
//  DesktopHUDView.swift
//  WallpaperEngineCore
//
//  Glassmorphic desktop overlay widgets featuring customizable typography clock,
//  live CPU/RAM/GPU telemetry monitors, Now Playing track card, real-time audio visualizer,
//  dynamic wallpaper accent color styling, and bidirectional macOS system preference (Light/Dark) synchronization.
//

import AppKit
import Foundation
import QuartzCore

@MainActor
public final class DesktopHUDView: NSView {

    // Visual Effect & Glass Container
    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()

    // 1. Clock & Date Widget
    private let clockContainer = NSView()
    private let timeLabel = NSTextField(labelWithString: "00:00:00")
    private let dateLabel = NSTextField(labelWithString: "Loading...")

    // 2. System Stats Widget
    private let statsContainer = NSStackView()
    private let cpuBadge = SystemStatBadgeView(title: "CPU", accentColor: WallpaperColorExtractor.auroraAccent)
    private let gpuBadge = SystemStatBadgeView(title: "GPU", accentColor: WallpaperColorExtractor.cyberpunkGridAccent)
    private let ramBadge = SystemStatBadgeView(title: "RAM", accentColor: WallpaperColorExtractor.starfieldAccent)
    private let fpsBadge = SystemStatBadgeView(title: "FPS", accentColor: WallpaperColorExtractor.gradientFlowAccent)

    // 3. Now Playing Widget
    private let nowPlayingContainer = NSView()
    private let musicGlyphLabel = NSTextField(labelWithString: "♫")
    private let trackTitleLabel = NSTextField(labelWithString: "No Media Playing")
    private let trackArtistLabel = NSTextField(labelWithString: "Spotify / Apple Music")
    private let miniEqualizerView = MiniEqualizerBarView()

    // 4. Audio Spectrum Visualizer Widget
    private let spectrumContainer = NSView()
    private var spectrumBars: [CALayer] = []

    // State, Accent Color & Appearance
    private var clockTimer: Timer?
    private var appearanceObserver: NSObjectProtocol?
    public var config: EngineConfig.HUDConfig = .init()
    public private(set) var currentTheme: WallpaperTheme = .fallback
    public private(set) var currentAccentColor: NSColor = WallpaperColorExtractor.auroraAccent

    public var isDarkMode: Bool {
        let appearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return appearance == .darkAqua
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGlassmorphicHierarchy()
        startClockTimer()
        setupAppearanceObserver()
        updateThemeAppearance()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGlassmorphicHierarchy()
        startClockTimer()
        setupAppearanceObserver()
        updateThemeAppearance()
    }

    deinit {
        // Observers cleaned up
    }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            clockTimer?.invalidate()
            clockTimer = nil
            teardownAppearanceObserver()
        } else if clockTimer == nil {
            startClockTimer()
            setupAppearanceObserver()
        }
    }

    public override func removeFromSuperview() {
        clockTimer?.invalidate()
        clockTimer = nil
        teardownAppearanceObserver()
        super.removeFromSuperview()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateThemeAppearance()
    }

    private func setupAppearanceObserver() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceStyleChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateThemeAppearance()
            }
        }
    }

    private func teardownAppearanceObserver() {
        if let obs = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            appearanceObserver = nil
        }
    }

    // MARK: - Glassmorphic Hierarchy Setup

    private func setupGlassmorphicHierarchy() {
        wantsLayer = true

        // Outer Glow & Shadow
        shadow = NSShadow()
        shadow?.shadowOffset = NSSize(width: 0, height: -6)
        shadow?.shadowBlurRadius = 18

        // Glassmorphic Backdrop
        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true

        if let glassLayer = visualEffectView.layer {
            glassLayer.cornerRadius = 20.0
            glassLayer.masksToBounds = true
            glassLayer.borderWidth = 1.0
        }
        addSubview(visualEffectView)

        // Vertical Content Stack
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16)
        ])

        setupClockWidget()
        setupStatsWidget()
        setupNowPlayingWidget()
        setupSpectrumWidget()
    }

    // MARK: - 1. Clock & Date Widget

    private func setupClockWidget() {
        clockContainer.wantsLayer = true
        clockContainer.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        timeLabel.alignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        dateLabel.alignment = .center
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        clockContainer.addSubview(timeLabel)
        clockContainer.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: clockContainer.topAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: clockContainer.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: clockContainer.trailingAnchor),

            dateLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: clockContainer.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: clockContainer.trailingAnchor),
            dateLabel.bottomAnchor.constraint(equalTo: clockContainer.bottomAnchor)
        ])

        contentStack.addArrangedSubview(clockContainer)
        updateClockDisplay()
    }

    // Static reusable date formatters to eliminate allocations on timer ticks
    private static let sharedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()

    private static let sharedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    public private(set) var isPaused: Bool = false

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        clockTimer?.invalidate()
        clockTimer = nil
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        startClockTimer()
        updateClockDisplay()
    }

    private func startClockTimer() {
        clockTimer?.invalidate()
        guard !isPaused && (config.showClock || config.showDate) else {
            clockTimer = nil
            return
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateClockDisplay()
            }
        }
    }

    private func updateClockDisplay() {
        guard !isPaused && (config.showClock || config.showDate) else { return }
        let now = Date()
        timeLabel.stringValue = Self.sharedTimeFormatter.string(from: now)
        dateLabel.stringValue = Self.sharedDateFormatter.string(from: now)
    }

    // MARK: - 2. System Stats Widget

    private func setupStatsWidget() {
        statsContainer.orientation = .horizontal
        statsContainer.alignment = .centerY
        statsContainer.spacing = 8
        statsContainer.distribution = .fillEqually
        statsContainer.translatesAutoresizingMaskIntoConstraints = false

        statsContainer.addArrangedSubview(cpuBadge)
        statsContainer.addArrangedSubview(gpuBadge)
        statsContainer.addArrangedSubview(ramBadge)
        statsContainer.addArrangedSubview(fpsBadge)

        NSLayoutConstraint.activate([
            statsContainer.heightAnchor.constraint(equalToConstant: 44),
            statsContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 290)
        ])

        contentStack.addArrangedSubview(statsContainer)
    }

    public func updateTelemetry(_ telemetry: SystemTelemetry) {
        cpuBadge.setValue(String(format: "%.0f%%", telemetry.cpuPercentage), progress: telemetry.cpuPercentage / 100.0)
        gpuBadge.setValue(String(format: "%.0f%%", telemetry.gpuPercentage), progress: telemetry.gpuPercentage / 100.0)
        ramBadge.setValue(String(format: "%.1fG", telemetry.ramUsedGB), progress: telemetry.ramPercentage / 100.0)
        fpsBadge.setValue("\(telemetry.fps)", progress: Float(telemetry.fps) / 144.0)
    }

    // MARK: - 3. Now Playing Widget

    private func setupNowPlayingWidget() {
        nowPlayingContainer.wantsLayer = true
        nowPlayingContainer.translatesAutoresizingMaskIntoConstraints = false

        if let layer = nowPlayingContainer.layer {
            layer.cornerRadius = 12
            layer.borderWidth = 1
        }

        musicGlyphLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        musicGlyphLabel.textColor = currentAccentColor
        musicGlyphLabel.translatesAutoresizingMaskIntoConstraints = false

        trackTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        trackTitleLabel.lineBreakMode = .byTruncatingTail
        trackTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        trackArtistLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        trackArtistLabel.lineBreakMode = .byTruncatingTail
        trackArtistLabel.translatesAutoresizingMaskIntoConstraints = false

        miniEqualizerView.translatesAutoresizingMaskIntoConstraints = false

        nowPlayingContainer.addSubview(musicGlyphLabel)
        nowPlayingContainer.addSubview(trackTitleLabel)
        nowPlayingContainer.addSubview(trackArtistLabel)
        nowPlayingContainer.addSubview(miniEqualizerView)

        NSLayoutConstraint.activate([
            nowPlayingContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 290),
            nowPlayingContainer.heightAnchor.constraint(equalToConstant: 48),

            musicGlyphLabel.leadingAnchor.constraint(equalTo: nowPlayingContainer.leadingAnchor, constant: 12),
            musicGlyphLabel.centerYAnchor.constraint(equalTo: nowPlayingContainer.centerYAnchor),
            musicGlyphLabel.widthAnchor.constraint(equalToConstant: 20),

            trackTitleLabel.topAnchor.constraint(equalTo: nowPlayingContainer.topAnchor, constant: 8),
            trackTitleLabel.leadingAnchor.constraint(equalTo: musicGlyphLabel.trailingAnchor, constant: 8),
            trackTitleLabel.trailingAnchor.constraint(equalTo: miniEqualizerView.leadingAnchor, constant: -8),

            trackArtistLabel.topAnchor.constraint(equalTo: trackTitleLabel.bottomAnchor, constant: 2),
            trackArtistLabel.leadingAnchor.constraint(equalTo: trackTitleLabel.leadingAnchor),
            trackArtistLabel.trailingAnchor.constraint(equalTo: trackTitleLabel.trailingAnchor),

            miniEqualizerView.trailingAnchor.constraint(equalTo: nowPlayingContainer.trailingAnchor, constant: -12),
            miniEqualizerView.centerYAnchor.constraint(equalTo: nowPlayingContainer.centerYAnchor),
            miniEqualizerView.widthAnchor.constraint(equalToConstant: 28),
            miniEqualizerView.heightAnchor.constraint(equalToConstant: 18)
        ])

        contentStack.addArrangedSubview(nowPlayingContainer)
    }

    public func updateNowPlaying(_ info: NowPlayingInfo?) {
        if let track = info, track.isPlaying {
            trackTitleLabel.stringValue = track.title
            trackArtistLabel.stringValue = "\(track.artist) • \(track.source)"
            musicGlyphLabel.textColor = track.source == "Spotify" ? NSColor.systemGreen : currentAccentColor
            miniEqualizerView.startAnimating()
        } else if let track = info {
            trackTitleLabel.stringValue = track.title
            trackArtistLabel.stringValue = "Paused • \(track.source)"
            musicGlyphLabel.textColor = isDarkMode ? NSColor.gray : NSColor.darkGray
            miniEqualizerView.stopAnimating()
        } else {
            trackTitleLabel.stringValue = "No Media Playing"
            trackArtistLabel.stringValue = "Spotify / Apple Music"
            musicGlyphLabel.textColor = isDarkMode ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.45, alpha: 1)
            miniEqualizerView.stopAnimating()
        }
    }

    // MARK: - 4. Audio Spectrum Visualizer Widget

    private func setupSpectrumWidget() {
        spectrumContainer.wantsLayer = true
        spectrumContainer.translatesAutoresizingMaskIntoConstraints = false

        let barCount = 16
        let totalWidth: CGFloat = 290
        let spacing: CGFloat = 4
        let barWidth: CGFloat = (totalWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
        let barMaxHeight: CGFloat = 36

        NSLayoutConstraint.activate([
            spectrumContainer.widthAnchor.constraint(equalToConstant: totalWidth),
            spectrumContainer.heightAnchor.constraint(equalToConstant: barMaxHeight)
        ])

        for i in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = 2
            let x = CGFloat(i) * (barWidth + spacing)
            bar.frame = CGRect(x: x, y: 0, width: barWidth, height: 4)
            spectrumContainer.layer?.addSublayer(bar)
            spectrumBars.append(bar)
        }

        contentStack.addArrangedSubview(spectrumContainer)
        updateSpectrumColors()
    }

    public func updateSpectrum(_ spectrum: AudioSpectrumData) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let maxHeight: CGFloat = 36
        for (i, bar) in spectrumBars.enumerated() {
            let val = CGFloat(i < spectrum.bands.count ? spectrum.bands[i] : 0.0)
            let h = max(3.0, val * maxHeight)
            var frame = bar.frame
            frame.size.height = h
            frame.origin.y = 0
            bar.frame = frame
        }

        miniEqualizerView.updateAudioEnergy(bass: spectrum.bass, amplitude: spectrum.amplitude)
        CATransaction.commit()
    }

    // MARK: - Dynamic Wallpaper Accent & Semantic Theme Synchronization

    public func applyTheme(_ theme: WallpaperTheme, animated: Bool = true) {
        self.currentTheme = theme
        self.currentAccentColor = theme.accent

        let duration = animated ? 0.40 : 0.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = animated

            // 1. Visual Effect & Outer Backdrop
            visualEffectView.material = theme.isDark ? .hudWindow : .sheet
            shadow?.shadowColor = theme.isDark ? NSColor.black.withAlphaComponent(0.45) : NSColor.black.withAlphaComponent(0.12)

            if let glassLayer = visualEffectView.layer {
                glassLayer.backgroundColor = theme.background.cgColor
                glassLayer.borderColor = theme.border.cgColor
            }

            // 2. Clock & Date Typography
            timeLabel.textColor = theme.textPrimary
            dateLabel.textColor = theme.textSecondary

            // 3. Now Playing Card Styling
            if let npLayer = nowPlayingContainer.layer {
                npLayer.backgroundColor = theme.surfaceElevated.cgColor
                npLayer.borderColor = theme.border.cgColor
            }

            trackTitleLabel.textColor = theme.textPrimary
            trackArtistLabel.textColor = theme.textSecondary
            musicGlyphLabel.textColor = theme.accent
            miniEqualizerView.updateAccentColor(theme.accent)

            // 4. Badges (CPU, GPU, RAM, FPS) with Harmonious Wallpaper Accents
            cpuBadge.updateTheme(
                accentColor: theme.primary,
                surfaceColor: theme.surface,
                textColor: theme.textPrimary,
                borderColor: theme.border,
                isDarkMode: theme.isDark
            )
            gpuBadge.updateTheme(
                accentColor: theme.accent,
                surfaceColor: theme.surface,
                textColor: theme.textPrimary,
                borderColor: theme.border,
                isDarkMode: theme.isDark
            )
            ramBadge.updateTheme(
                accentColor: theme.secondary,
                surfaceColor: theme.surface,
                textColor: theme.textPrimary,
                borderColor: theme.border,
                isDarkMode: theme.isDark
            )
            fpsBadge.updateTheme(
                accentColor: theme.accent,
                surfaceColor: theme.surface,
                textColor: theme.textPrimary,
                borderColor: theme.border,
                isDarkMode: theme.isDark
            )

            // 5. Mini Equalizer & Spectrum Bars
            updateSpectrumColors(theme: theme)
        }
    }

    public func applyWallpaperAccentColor(_ color: NSColor) {
        self.currentAccentColor = color
        let pal = ExtractedPalette(
            dominant: CodableRGBA(nsColor: color),
            vibrant: CodableRGBA(nsColor: color),
            secondary: CodableRGBA(nsColor: WallpaperColorExtractor.secondaryAccentColor(for: color)),
            darkMuted: CodableRGBA(nsColor: NSColor(calibratedHue: color.hueComponent, saturation: 0.35, brightness: 0.12, alpha: 1.0)),
            lightMuted: CodableRGBA(nsColor: NSColor(calibratedHue: color.hueComponent, saturation: 0.20, brightness: 0.94, alpha: 1.0)),
            averageLuminance: isDarkMode ? 0.15 : 0.85,
            isPredominantlyDark: isDarkMode
        )
        let generated = AdaptiveThemeGenerator.shared.generateTheme(
            from: pal,
            settings: ThemeSettings(appearancePreference: isDarkMode ? .preferDark : .preferLight)
        )
        applyTheme(generated, animated: true)
        self.currentAccentColor = color
    }

    public func updateThemeAppearance() {
        applyWallpaperAccentColor(currentAccentColor)
    }

    private func updateSpectrumColors(theme: WallpaperTheme? = nil) {
        let t = theme ?? currentTheme
        let total = max(1, spectrumBars.count - 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in spectrumBars.enumerated() {
            let progress = CGFloat(i) / CGFloat(total)
            let color = interpolateColor(from: t.primary, to: t.secondary, progress: progress)
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()
    }

    private func interpolateColor(from start: NSColor, to end: NSColor, progress: CGFloat) -> NSColor {
        guard let c1 = start.usingColorSpace(.sRGB),
              let c2 = end.usingColorSpace(.sRGB) else { return start }
        let p = max(0.0, min(1.0, progress))
        let r = c1.redComponent + (c2.redComponent - c1.redComponent) * p
        let g = c1.greenComponent + (c2.greenComponent - c1.greenComponent) * p
        let b = c1.blueComponent + (c2.blueComponent - c1.blueComponent) * p
        let a = c1.alphaComponent + (c2.alphaComponent - c1.alphaComponent) * p
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Configuration & Layout Updates

    public func applyConfig(_ hudConfig: EngineConfig.HUDConfig) {
        self.config = hudConfig
        clockContainer.isHidden = !hudConfig.showClock
        dateLabel.isHidden = !hudConfig.showDate
        statsContainer.isHidden = !hudConfig.showSystemStats
        nowPlayingContainer.isHidden = !hudConfig.showNowPlaying
        spectrumContainer.isHidden = !hudConfig.showAudioVisualizer
        self.isHidden = !hudConfig.isEnabled
        startClockTimer()
    }

    public func updatePlacement(in screenFrame: CGRect) {
        let hudWidth: CGFloat = 326
        let targetSize = fittingSize
        let hudHeight = max(90, targetSize.height)

        let marginX: CGFloat = 28
        let marginY: CGFloat = 40

        var x: CGFloat = 0
        var y: CGFloat = 0

        switch config.position {
        case .topRight:
            x = screenFrame.width - hudWidth - marginX
            y = screenFrame.height - hudHeight - marginY
        case .topLeft:
            x = marginX
            y = screenFrame.height - hudHeight - marginY
        case .bottomRight:
            x = screenFrame.width - hudWidth - marginX
            y = marginY + 20
        case .bottomLeft:
            x = marginX
            y = marginY + 20
        case .topCenter:
            x = (screenFrame.width - hudWidth) / 2.0
            y = screenFrame.height - hudHeight - marginY
        }

        self.frame = CGRect(x: x, y: y, width: hudWidth, height: hudHeight)
    }
}

// MARK: - Custom Subview Components

@MainActor
final class SystemStatBadgeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "0%")
    private let progressLayer = CALayer()
    private var currentAccentColor: NSColor

    init(title: String, accentColor: NSColor) {
        self.currentAccentColor = accentColor
        super.init(frame: .zero)
        wantsLayer = true

        if let l = layer {
            l.cornerRadius = 10
            l.backgroundColor = NSColor(white: 0.15, alpha: 0.45).cgColor
            l.borderWidth = 1
            l.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            l.masksToBounds = true
        }

        progressLayer.backgroundColor = accentColor.withAlphaComponent(0.35).cgColor
        progressLayer.frame = .zero
        layer?.addSublayer(progressLayer)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        titleLabel.textColor = accentColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateTheme(accentColor: NSColor, surfaceColor: NSColor, textColor: NSColor, borderColor: NSColor, isDarkMode: Bool) {
        self.currentAccentColor = accentColor
        titleLabel.textColor = accentColor
        valueLabel.textColor = textColor
        progressLayer.backgroundColor = accentColor.withAlphaComponent(isDarkMode ? 0.35 : 0.25).cgColor

        if let l = layer {
            l.backgroundColor = surfaceColor.cgColor
            l.borderColor = borderColor.cgColor
        }
    }

    func updateTheme(accentColor: NSColor, isDarkMode: Bool) {
        self.currentAccentColor = accentColor
        titleLabel.textColor = accentColor
        valueLabel.textColor = isDarkMode ? .white : NSColor(white: 0.10, alpha: 1.0)
        progressLayer.backgroundColor = accentColor.withAlphaComponent(isDarkMode ? 0.35 : 0.25).cgColor

        if let l = layer {
            l.backgroundColor = isDarkMode
                ? NSColor(white: 0.15, alpha: 0.45).cgColor
                : NSColor(white: 0.0, alpha: 0.05).cgColor
            l.borderColor = isDarkMode
                ? NSColor(white: 1.0, alpha: 0.12).cgColor
                : NSColor(white: 0.0, alpha: 0.08).cgColor
        }
    }

    func setValue(_ string: String, progress: Float) {
        valueLabel.stringValue = string
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let p = CGFloat(max(0.0, min(1.0, progress)))
        progressLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * p, height: bounds.height)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        progressLayer.frame.size.height = bounds.height
    }
}

@MainActor
final class MiniEqualizerBarView: NSView {
    private var bars: [CALayer] = []
    private var isPlaying: Bool = false
    private var currentAccentColor: NSColor = .systemPink

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        for i in 0..<5 {
            let bar = CALayer()
            bar.cornerRadius = 1.5
            bar.backgroundColor = currentAccentColor.cgColor
            bar.frame = CGRect(x: CGFloat(i) * (barWidth + gap), y: 0, width: barWidth, height: 4)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateAccentColor(_ color: NSColor) {
        self.currentAccentColor = color
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()
    }

    func startAnimating() { isPlaying = true }
    func stopAnimating() {
        isPlaying = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.frame.size.height = 3
        }
        CATransaction.commit()
    }

    func updateAudioEnergy(bass: Float, amplitude: Float) {
        guard isPlaying else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let heights: [CGFloat] = [
            CGFloat(max(4.0, amplitude * 18.0)),
            CGFloat(max(4.0, bass * 16.0)),
            CGFloat(max(4.0, (amplitude + bass) * 10.0)),
            CGFloat(max(4.0, amplitude * 14.0)),
            CGFloat(max(4.0, bass * 12.0))
        ]
        for (i, bar) in bars.enumerated() {
            let h = min(18.0, heights[i % heights.count])
            var f = bar.frame
            f.size.height = h
            bar.frame = f
        }
        CATransaction.commit()
    }
}
