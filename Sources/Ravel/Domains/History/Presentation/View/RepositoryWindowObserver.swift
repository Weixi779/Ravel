//
//  RepositoryWindowObserver.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

import AppKit
import CoreServices
import SwiftUI

/// NSWindow owns visibility and keyboard focus, including when the app shares
/// the screen with an editor. Observe the window containing this repository.
struct RepositoryWindowObserver: NSViewRepresentable {
    let session: LogSession
    let isSelectingSplit: () -> Bool

    func makeNSView(context _: Context) -> RepositoryWindowObservationView {
        RepositoryWindowObservationView()
    }

    func updateNSView(_ view: RepositoryWindowObservationView, context _: Context) {
        view.observe(session: session, isSelectingSplit: isSelectingSplit)
    }

    static func dismantleNSView(_ view: RepositoryWindowObservationView, coordinator _: ()) {
        view.stop()
    }
}

@MainActor
final class RepositoryWindowObservationView: NSView {
    private weak var session: LogSession?
    private var isSelectingSplit: () -> Bool = { false }
    private var workspaceURL: URL?
    private var backingURL: URL?
    private var stream: FSEventStreamRef?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var visible = false
    private var focused = false
    private var pendingCheck = false
    private var pendingDisk = false
    private var pendingPaths = Set<String>()
    private var pendingFocus = false

    func observe(session: LogSession, isSelectingSplit: @escaping () -> Bool) {
        self.session = session
        self.isSelectingSplit = isSelectingSplit
        let workspace = session.log?.repositoryURL
        let backing = session.log?.backingRepositoryURL
        guard workspaceURL != workspace || backingURL != backing else { return }
        stop()
        workspaceURL = workspace
        backingURL = backing
        attach()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stop()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        guard let window, let workspaceURL, let backingURL else { return }
        let center = NotificationCenter.default
        for event in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            center.addObserver(self, selector: #selector(windowChanged), name: event, object: window)
        }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let roots = [workspaceURL.path, backingURL.appendingPathComponent("op_heads").path]
        stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            let missedEvents = (0 ..< count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
            MainActor.assumeIsolated {
                Unmanaged<RepositoryWindowObservationView>.fromOpaque(info).takeUnretainedValue().filesChanged(paths, missedEvents: missedEvents)
            }
        }, &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
        windowChanged()
    }

    @objc
    private func windowChanged() {
        let nowVisible = window?.occlusionState.contains(.visible) == true && window?.isMiniaturized == false
        let nowFocused = nowVisible && window?.isKeyWindow == true
        let becameVisible = nowVisible && !visible
        let becameFocused = nowFocused && !focused
        visible = nowVisible
        focused = nowFocused
        if !visible {
            pendingCheck = true
            pendingDisk = true
            pendingFocus = false
        } else if becameVisible || becameFocused {
            schedule(checkDisk: becameVisible, focus: becameFocused)
        } else if !nowFocused {
            pendingFocus = false
        }
    }

    private func filesChanged(_ paths: [String], missedEvents: Bool) {
        guard let workspaceURL, let backingURL else { return }
        let root = workspaceURL.path + "/"
        let heads = backingURL.appendingPathComponent("op_heads").path
        var op = missedEvents
        var disk = false
        for path in paths {
            if path == heads || path.hasPrefix(heads + "/") { op = true }
            guard path.hasPrefix(root) else { continue }
            let relative = path.dropFirst(root.count).split(separator: "/")
            if !relative.contains(".jj"), !relative.contains(".git") {
                disk = true
                if visible && !pendingDisk {
                    pendingPaths.insert(String(path.dropFirst(root.count)))
                    if relative.last == ".gitignore" || pendingPaths.count > 256 { pendingDisk = true }
                }
            }
        }
        if op || disk { schedule(checkDisk: missedEvents || !visible, focus: false) }
    }

    private func schedule(checkDisk: Bool, focus: Bool) {
        pendingCheck = true
        pendingDisk = pendingDisk || checkDisk
        pendingFocus = pendingFocus || focus
        guard visible, task == nil else { return }
        let epoch = generation
        task = Task { [weak self] in
            await Task.yield()
            guard let self, generation == epoch else { return }
            while pendingCheck, visible, !Task.isCancelled {
                let paths = pendingDisk ? [] : Array(pendingPaths)
                let disk = pendingDisk || !paths.isEmpty
                pendingPaths.removeAll()
                let snapshot = pendingFocus && focused
                pendingCheck = false
                pendingDisk = false
                pendingFocus = false
                guard !isSelectingSplit(), let session else { continue }
                await session.reconcileWindow(checkDisk: disk || snapshot, focus: snapshot, paths: paths, isFocused: { [weak self] in self?.focused == true }) { [weak self] in
                    guard let self else { return false }
                    return generation == epoch && visible && !isSelectingSplit()
                }
            }
            if generation == epoch { task = nil }
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        generation += 1
        task?.cancel()
        task = nil
        pendingPaths.removeAll()
        pendingCheck = false
        pendingDisk = false
        pendingFocus = false
        focused = false
        visible = false
    }
}
