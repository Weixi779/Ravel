// Created by weixi on 2026/09/16.

import Foundation
import Observation
import Synchronization
import Testing
import UserDefaultsKit
@testable import Ravel

@MainActor
struct UserDefaultsIntegrationTests {
    @Test func externalStorageChangesUpdateBothSessionsRecentWorkspaces() throws {
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

    @Test func sessionUsesExistingKeysWithoutChangingTheirFormat() throws {
        let suite = "RavelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/repo", forKey: "lastRepositoryPath")
        defaults.set(["/repo", "/other"], forKey: "recentRepositoryPaths")
        defaults.set("/bin/jj", forKey: "jjExecutablePath")

        let session = LogSession(defaults: defaults)
        #expect(session.recentPaths == ["/repo", "/other"])
        session.setExecutable(URL(fileURLWithPath: "/new/jj"))
        session.forget("/repo")
        #expect(defaults.object(forKey: "lastRepositoryPath") == nil)
        #expect(defaults.string(forKey: "jjExecutablePath") == "/new/jj")
        #expect(defaults.stringArray(forKey: "recentRepositoryPaths") == ["/other"])
    }

    @Test func forgettingAWorkspaceStillNotifiesTheObservableSession() throws {
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

    @Test func separateSessionEnvironmentsKeepIndependentValues() throws {
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
        first.setExecutable(URL(fileURLWithPath: "/first/jj"))
        second.setExecutable(URL(fileURLWithPath: "/second/jj"))
        #expect(first.recentPaths.isEmpty)
        #expect(second.recentPaths == ["/second"])
        #expect(firstDefaults.stringArray(forKey: "recentRepositoryPaths") == [])
        #expect(secondDefaults.stringArray(forKey: "recentRepositoryPaths") == ["/second"])
        #expect(firstDefaults.string(forKey: "jjExecutablePath") == "/first/jj")
        #expect(secondDefaults.string(forKey: "jjExecutablePath") == "/second/jj")
    }
}
