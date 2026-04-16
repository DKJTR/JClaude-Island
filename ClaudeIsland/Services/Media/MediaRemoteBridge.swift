//
//  MediaRemoteBridge.swift
//  DynamicIsland
//
//  Bridge to Apple's private MediaRemote.framework via dlopen/dlsym
//

import Foundation

/// Bridge to MediaRemote private framework for Now Playing info and control
final class MediaRemoteBridge: @unchecked Sendable {
    static let shared = MediaRemoteBridge()

    // MARK: - Function Types

    private typealias MRMediaRemoteGetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    private typealias MRMediaRemoteSendCommandFn =
        @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
    private typealias MRMediaRemoteRegisterFn =
        @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteGetNowPlayingAppBundleIdFn =
        @convention(c) (DispatchQueue, @escaping (CFString) -> Void) -> Void

    // MARK: - Resolved Functions

    private let getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFn?
    private let sendCommand: MRMediaRemoteSendCommandFn?
    private let registerForNotifications: MRMediaRemoteRegisterFn?
    private let getNowPlayingAppBundleId: MRMediaRemoteGetNowPlayingAppBundleIdFn?

    // MARK: - Commands

    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    // MARK: - Known Dictionary Keys

    static let kTitle = "kMRMediaRemoteNowPlayingInfoTitle"
    static let kArtist = "kMRMediaRemoteNowPlayingInfoArtist"
    static let kAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let kArtworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let kDuration = "kMRMediaRemoteNowPlayingInfoDuration"
    static let kElapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let kPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    static let kTimestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"

    // MARK: - Init

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            getNowPlayingInfo = nil
            sendCommand = nil
            registerForNotifications = nil
            getNowPlayingAppBundleId = nil
            return
        }

        getNowPlayingInfo = unsafeBitCast(
            dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
            to: MRMediaRemoteGetNowPlayingInfoFn?.self
        )

        sendCommand = unsafeBitCast(
            dlsym(handle, "MRMediaRemoteSendCommand"),
            to: MRMediaRemoteSendCommandFn?.self
        )

        registerForNotifications = unsafeBitCast(
            dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications"),
            to: MRMediaRemoteRegisterFn?.self
        )

        getNowPlayingAppBundleId = unsafeBitCast(
            dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationBundleIdentifier"),
            to: MRMediaRemoteGetNowPlayingAppBundleIdFn?.self
        )
    }

    // MARK: - Public API

    var isAvailable: Bool {
        getNowPlayingInfo != nil && sendCommand != nil
    }

    func fetchNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        guard let fn = getNowPlayingInfo else {
            completion([:])
            return
        }
        fn(DispatchQueue.main) { cfDict in
            let dict = cfDict as NSDictionary as! [String: Any]
            completion(dict)
        }
    }

    func fetchNowPlayingBundleId(completion: @escaping (String) -> Void) {
        guard let fn = getNowPlayingAppBundleId else {
            completion("")
            return
        }
        fn(DispatchQueue.main) { cfString in
            completion(cfString as String)
        }
    }

    func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }

    func registerForNowPlayingNotifications() {
        registerForNotifications?(DispatchQueue.main)
    }
}
