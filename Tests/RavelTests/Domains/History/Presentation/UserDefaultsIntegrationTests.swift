//
//  UserDefaultsIntegrationTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Observation
@testable import Ravel
import Synchronization
import Testing
import UserDefaultsKit

@MainActor
struct UserDefaultsIntegrationTests {
    @Test
    func graphStylePersistsAndUnknownStylesFallBackToRounded() throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LogSession(defaults: defaults)
        #expect(first.graphStyle == .rounded)
        first.graphStyle = .curved
        #expect(LogSession(defaults: defaults).graphStyle == .curved)
        defaults.set("future-style", forKey: "historyGraphStyle")
        #expect(first.graphStyle == .rounded)
    }

    @Test
    func externalStorageChangesUpdateBothSessionsRecentWorkspaces() throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        let first = LogSession(store: store)
        let second = LogSession(store: store)
        let changes = Mutex(0)
        withObservationTracking {
            _ = first.recentPaths
            _ = second.recentPaths
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        defaults.set(["/external"], forKey: "recentRepositoryPaths")

        #expect(changes.withLock { $0 } == 1)
        #expect(first.recentPaths == ["/external"])
        #expect(second.recentPaths == ["/external"])
        first.forget("/external")
        #expect(second.recentPaths.isEmpty)
    }

    @Test
    func sessionUsesExistingKeysWithoutChangingTheirFormat() throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/repo", forKey: "lastRepositoryPath")
        defaults.set(["/repo", "/other"], forKey: "recentRepositoryPaths")

        let session = LogSession(defaults: defaults)
        #expect(session.recentPaths == ["/repo", "/other"])
        session.forget("/repo")
        #expect(defaults.object(forKey: "lastRepositoryPath") == nil)
        #expect(defaults.stringArray(forKey: "recentRepositoryPaths") == ["/other"])
    }

    @Test
    func forgettingAWorkspaceStillNotifiesTheObservableSession() throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/repo", forKey: "lastRepositoryPath")
        defaults.set(["/repo", "/other"], forKey: "recentRepositoryPaths")
        let session = LogSession(defaults: defaults)
        let changes = Mutex(0)

        withObservationTracking {
            _ = session.recentPaths
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        session.forget("/repo")

        #expect(changes.withLock { $0 } > 0)
        #expect(session.recentPaths == ["/other"])
        #expect(defaults.stringArray(forKey: "recentRepositoryPaths") == ["/other"])
        #expect(defaults.object(forKey: "lastRepositoryPath") == nil)
    }

    @Test
    func separateSessionEnvironmentsKeepIndependentValues() throws {
        let firstSuite = "RavelTests.\(UUID())"
        let secondSuite = "RavelTests.\(UUID())"
        let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
        let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        firstDefaults.set(["/first"], forKey: "recentRepositoryPaths")
        secondDefaults.set(["/second"], forKey: "recentRepositoryPaths")
        let first = LogSession(defaults: firstDefaults)
        let second = LogSession(defaults: secondDefaults)
        first.forget("/first")
        #expect(first.recentPaths.isEmpty)
        #expect(second.recentPaths == ["/second"])
        #expect(firstDefaults.stringArray(forKey: "recentRepositoryPaths") == [])
        #expect(secondDefaults.stringArray(forKey: "recentRepositoryPaths") == ["/second"])
    }
}
