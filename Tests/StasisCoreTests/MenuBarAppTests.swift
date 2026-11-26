import Foundation
import Testing
@testable import StasisCore

private func proc(_ pid: pid_t, parent: pid_t = 1, path: String, stopped: Bool = false) -> ProcessRecord {
    ProcessRecord(
        pid: pid, parentPid: parent, name: (path as NSString).lastPathComponent,
        executablePath: path, isStopped: stopped, residentBytes: 0
    )
}

private let studio = RunningApp(
    pid: 200, name: "Android Studio", bundleIdentifier: "com.google.android.studio",
    bundlePath: "/Applications/Android Studio.app"
)
private let shottr = RunningApp(
    pid: 400, name: "Shottr", bundleIdentifier: "cc.ffitch.shottr", bundlePath: "/Applications/Shottr.app",
    hasDockIcon: false
)

@Suite struct ListedAccessoryBundleTests {
    @Test func acceptsThirdPartyBundlesWhereverInstalled() {
        #expect(Workspace.isListedAccessoryBundle(path: "/Applications/Shottr.app"))
        #expect(Workspace.isListedAccessoryBundle(path: "/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app"))
        #expect(Workspace.isListedAccessoryBundle(path: "/Users/me/Library/Application Support/JetBrains/Daemon/bundles/current/jetbrainsd.app"))
    }

    @Test func rejectsSystemBundlesAndBundlelessProcesses() {
        #expect(!Workspace.isListedAccessoryBundle(path: "/System/Library/CoreServices/ControlCenter.app"))
        #expect(!Workspace.isListedAccessoryBundle(path: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc"))
        #expect(!Workspace.isListedAccessoryBundle(path: nil))
    }
}

@Suite struct MenuBarAppGroupingTests {
    @Test func menuBarAppStartedByAListedAppIsOneOfItsProcesses() {
        let cefServer = RunningApp(
            pid: 201, name: "cef_server", bundleIdentifier: "com.jetbrains.cefserver",
            bundlePath: "/Users/me/Library/Application Support/Google/AndroidStudio/plugins/jcef/Frameworks/cef_server.app",
            hasDockIcon: false
        )
        let processes = [
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(201, parent: 200, path: "/Users/me/Library/Application Support/Google/AndroidStudio/plugins/jcef/Frameworks/cef_server.app/Contents/MacOS/cef_server"),
        ]
        let groups = ProcessGrouper.group(apps: [studio, cefServer], processes: processes)
        #expect(groups.map(\.app.pid) == [200])
        #expect(groups[0].processes.map(\.pid) == [200, 201])
    }

    @Test func menuBarAppInsideAListedAppsBundleIsOneOfItsProcessesEvenWhenLaunchdStartedIt() {
        let loginItem = RunningApp(
            pid: 500, name: "Studio Login Item", bundleIdentifier: "com.google.android.studio.login",
            bundlePath: "/Applications/Android Studio.app/Contents/Library/LoginItems/X.app",
            hasDockIcon: false
        )
        let processes = [
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(500, parent: 1, path: "/Applications/Android Studio.app/Contents/Library/LoginItems/X.app/Contents/MacOS/X"),
        ]
        let groups = ProcessGrouper.group(apps: [studio, loginItem], processes: processes)
        #expect(groups.map(\.app.pid) == [200])
        #expect(groups[0].processes.map(\.pid) == [200, 500])
    }

    @Test func dockAppStartedByAnotherAppKeepsItsOwnRow() {
        let processes = [
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(400, parent: 200, path: "/Applications/Shottr.app/Contents/MacOS/Shottr"),
        ]
        var dockShottr = shottr
        dockShottr.hasDockIcon = true
        let groups = ProcessGrouper.group(apps: [studio, dockShottr], processes: processes)
        #expect(Set(groups.map(\.app.pid)) == [200, 400])
    }

    @Test func standaloneMenuBarAppGetsItsOwnRow() {
        let processes = [
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(400, path: "/Applications/Shottr.app/Contents/MacOS/Shottr"),
        ]
        let groups = ProcessGrouper.group(apps: [studio, shottr], processes: processes)
        #expect(Set(groups.map(\.app.pid)) == [200, 400])
    }
}

@Suite struct AppFilterTests {
    private let dockApp = AppGroup(app: studio, processes: [proc(200, path: "/s")])
    private let menuBarApp = AppGroup(app: shottr, processes: [proc(400, path: "/m")])

    @Test func allKeepsEveryAppInOrder() {
        #expect(AppFilter.all.filtered([menuBarApp, dockApp]) == [menuBarApp, dockApp])
    }

    @Test func dockKeepsOnlyAppsWithADockIcon() {
        #expect(AppFilter.dock.filtered([menuBarApp, dockApp]) == [dockApp])
    }

    @Test func menuBarKeepsOnlyAppsWithoutADockIcon() {
        #expect(AppFilter.menuBar.filtered([menuBarApp, dockApp]) == [menuBarApp])
    }

    @Test func reportsTheNotRunningAppsItHides() {
        let pausedMenuBar = AppGroup(app: shottr, processes: [proc(400, path: "/m", stopped: true)])
        let pausedDock = AppGroup(app: studio, processes: [proc(200, path: "/s", stopped: true)])
        let groups = [dockApp, menuBarApp, pausedMenuBar, pausedDock]
        #expect(AppFilter.dock.hiddenNotRunning(in: groups) == [pausedMenuBar])
        #expect(AppFilter.menuBar.hiddenNotRunning(in: groups) == [pausedDock])
        #expect(AppFilter.all.hiddenNotRunning(in: groups).isEmpty)
    }

    @Test func complementShowsWhatTheFilterHides() {
        #expect(AppFilter.dock.complement == .menuBar)
        #expect(AppFilter.menuBar.complement == .dock)
        #expect(AppFilter.all.complement == nil)
    }
}

@Suite struct MenuBarAppSignalTests {
    private let running = AppGroup(app: studio, processes: [proc(200, path: "/s")])
    private let menuBar = AppGroup(app: shottr, processes: [proc(400, path: "/m"), proc(401, path: "/n")])
    private let pausedMenuBar = AppGroup(app: shottr, processes: [proc(400, path: "/m", stopped: true)])

    @Test func pauseAllLeavesMenuBarAppsRunning() {
        #expect(SignalPlan.pauseAllTargets(in: [running, menuBar], sparing: nil).map(\.app.pid) == [200])
        #expect(SignalPlan.stopAll([running, menuBar]).pids == [200])
    }

    @Test func menuBarAppCanBePausedOnItsOwn() {
        let plan = SignalPlan.toggle(menuBar)
        #expect(plan.signal == .stop)
        #expect(plan.pids == [400, 401])
    }

    @Test func resumeAllIncludesPausedMenuBarApps() {
        #expect(SignalPlan.continueAll([running, pausedMenuBar]).pids == [400])
    }
}
