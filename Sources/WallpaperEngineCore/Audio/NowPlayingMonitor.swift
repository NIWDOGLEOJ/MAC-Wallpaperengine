//
//  NowPlayingMonitor.swift
//  WallpaperEngineCore
//
//  Live track metadata observer for Spotify and Apple Music,
//  extracting title, artist, album, and playback states via
//  Darwin distributed notifications and low-overhead AppleScript.
//

import AppKit
import Foundation
import OSLog

public struct NowPlayingInfo: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var source: String // "Spotify" or "Apple Music"
    public var isPlaying: Bool
    public var playbackPosition: TimeInterval
    public var duration: TimeInterval

    public init(
        title: String,
        artist: String,
        album: String,
        source: String,
        isPlaying: Bool,
        playbackPosition: TimeInterval = 0.0,
        duration: TimeInterval = 0.0
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.isPlaying = isPlaying
        self.playbackPosition = playbackPosition
        self.duration = duration
    }

    public static let empty = NowPlayingInfo(
        title: "",
        artist: "",
        album: "",
        source: "None",
        isPlaying: false
    )

    public init() {
        self.init(title: "", artist: "", album: "", source: "None", isPlaying: false)
    }
}

public final class NowPlayingMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "NowPlayingMonitor")
    private let lock = NSLock()

    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.wallpaperengine.nowplaying", qos: .utility)
    private var isRunning: Bool = false
    public private(set) var currentTrack: NowPlayingInfo?

    public var onNowPlayingChange: (@Sendable (NowPlayingInfo?) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        registerDistributedNotifications()
        startPolling()
        queryCurrentTrack()
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        pollTimer?.cancel()
        pollTimer = nil
        lock.unlock()

        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Distributed Notifications

    private func registerDistributedNotifications() {
        // Spotify Notification
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: nil
        ) { [weak self] notif in
            self?.handleSpotifyNotification(notif)
        }

        // Apple Music Notification
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: nil
        ) { [weak self] notif in
            self?.handleAppleMusicNotification(notif)
        }
    }

    private func handleSpotifyNotification(_ notif: Notification) {
        guard let userDict = notif.userInfo as? [String: Any] else {
            queryCurrentTrack()
            return
        }
        let state = userDict["Player State"] as? String ?? "Paused"
        let isPlaying = (state == "Playing" || state == "kPSP")
        let name = userDict["Name"] as? String ?? ""
        let artist = userDict["Artist"] as? String ?? ""
        let album = userDict["Album"] as? String ?? ""

        guard !name.isEmpty else {
            updateTrack(nil)
            return
        }

        let info = NowPlayingInfo(
            title: name,
            artist: artist,
            album: album,
            source: "Spotify",
            isPlaying: isPlaying
        )
        updateTrack(info)
    }

    private func handleAppleMusicNotification(_ notif: Notification) {
        guard let userDict = notif.userInfo as? [String: Any] else {
            queryCurrentTrack()
            return
        }
        let state = userDict["Player State"] as? String ?? "Paused"
        let isPlaying = (state == "Playing")
        let name = userDict["Name"] as? String ?? ""
        let artist = userDict["Artist"] as? String ?? ""
        let album = userDict["Album"] as? String ?? ""

        guard !name.isEmpty else {
            updateTrack(nil)
            return
        }

        let info = NowPlayingInfo(
            title: name,
            artist: artist,
            album: album,
            source: "Apple Music",
            isPlaying: isPlaying
        )
        updateTrack(info)
    }

    // MARK: - Background Polling

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            self?.queryCurrentTrack()
        }
        timer.resume()
        self.pollTimer = timer
    }

    public func queryCurrentTrack() {
        pollQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Check Spotify if running
            if let spotifyInfo = self.querySpotifyScript() {
                self.updateTrack(spotifyInfo)
                return
            }

            // 2. Check Apple Music if running
            if let musicInfo = self.queryAppleMusicScript() {
                self.updateTrack(musicInfo)
                return
            }

            // No active media player running
            self.updateTrack(nil)
        }
    }

    private func querySpotifyScript() -> NowPlayingInfo? {
        let scriptSource = """
        if application "Spotify" is running then
            tell application "Spotify"
                set pState to (player state as string)
                if pState is "playing" then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & pState
                end if
            end tell
        end if
        return ""
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let stringValue = result.stringValue, !stringValue.isEmpty else {
            return nil
        }

        let parts = stringValue.components(separatedBy: "|||")
        guard parts.count >= 4 else { return nil }

        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            source: "Spotify",
            isPlaying: parts[3].lowercased() == "playing"
        )
    }

    private func queryAppleMusicScript() -> NowPlayingInfo? {
        let scriptSource = """
        if application "Music" is running then
            tell application "Music"
                set pState to (player state as string)
                if pState is "playing" then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & pState
                end if
            end tell
        end if
        return ""
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let stringValue = result.stringValue, !stringValue.isEmpty else {
            return nil
        }

        let parts = stringValue.components(separatedBy: "|||")
        guard parts.count >= 4 else { return nil }

        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            source: "Apple Music",
            isPlaying: parts[3].lowercased() == "playing"
        )
    }

    private func updateTrack(_ info: NowPlayingInfo?) {
        lock.lock()
        let changed = (currentTrack != info)
        currentTrack = info
        lock.unlock()

        if changed {
            onNowPlayingChange?(info)
        }
    }
}
