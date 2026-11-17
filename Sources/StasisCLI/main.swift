import AppKit
import Darwin
import Foundation
import StasisCore

let usage = """
    usage: stasis <command> [options]

      list [--json] [--processes]      running apps with pause state and memory
      pause <app>                      pause an app (bundle id or name)
      resume <app>                     resume an app (bundle id or name)
      kill <app>                       kill an app with SIGKILL; unsaved work is lost
      pause-all [--include-frontmost]  pause every app except the one in front
      resume-all                       resume every paused or partially paused app

    exit status: 1 usage, 2 no or ambiguous app, 3 a signal failed
    """

enum ExitCode {
    static let usage: Int32 = 1
    static let noApp: Int32 = 2
    static let signalFailed: Int32 = 3
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func snapshot(includeUsage: Bool) -> [AppGroup] {
    Workspace.snapshot(of: Workspace.regularApplications(), includeUsage: includeUsage)
}

/// Sends the plan, reports every failure, and tells the menu bar app to refresh.
func send(_ plan: SignalPlan) {
    var failures = 0
    // Run from a terminal that is itself a target, this process is a descendant of it and in the
    // plan; stopping ourselves halfway would leave the rest unsignalled.
    for pid in plan.pids where pid != getpid() && kill(pid, plan.signal.number) != 0 {
        let code = errno
        // Killing a parent can take its children down before their turn comes.
        if plan.signal == .kill && code == ESRCH { continue }
        failures += 1
        FileHandle.standardError.write(Data("kill(\(pid)) failed: \(String(cString: strerror(code)))\n".utf8))
    }
    Workspace.postDidChange()
    if failures > 0 {
        fail("\(failures) of \(plan.pids.count) processes could not be signalled", code: ExitCode.signalFailed)
    }
}

func resolve(_ query: String, in groups: [AppGroup]) -> AppGroup {
    switch AppMatcher.match(query, in: groups) {
    case .found(let group):
        return group
    case .notFound:
        let hint = query.count < AppMatcher.minimumPartialQueryLength
            ? "partial names need at least \(AppMatcher.minimumPartialQueryLength) characters"
            : "see `stasis list`"
        fail("no running app matches \"\(query)\"; \(hint)", code: ExitCode.noApp)
    case .ambiguous(let candidates):
        fail("\"\(query)\" matches several apps:\n" + candidates.map { "  \($0.app.name)" }.joined(separator: "\n"),
             code: ExitCode.noApp)
    }
}

func printTable(_ groups: [AppGroup], processes: Bool) {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    let width = groups.map(\.app.name.count).max() ?? 0
    for group in groups {
        let memory = formatter.string(fromByteCount: Int64(group.totalResidentBytes))
        print("\(group.app.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(group.state.label.padding(toLength: 7, withPad: " ", startingAt: 0))  \(memory)")
        guard processes else { continue }
        for process in group.processes {
            let memory = formatter.string(fromByteCount: Int64(process.residentBytes))
            print("    \(process.pid)  \(process.isStopped ? "paused " : "running")  \(memory)  \(process.name)")
        }
    }
}

func printJSON(_ groups: [AppGroup], processes: Bool) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! encoder.encode(groups.map { AppSummary($0, includeProcesses: processes) })
    print(String(decoding: data, as: UTF8.self))
}

/// Rejects anything but the flags a command knows, so a typo never silently runs the command.
func parse(_ arguments: [String], allowedFlags: Set<String>, positionals: Int) -> (flags: Set<String>, positionals: [String]) {
    let flags = Set(arguments.filter { $0.hasPrefix("-") })
    let rest = arguments.filter { !$0.hasPrefix("-") }
    guard flags.isSubset(of: allowedFlags), rest.count == positionals else { fail(usage, code: ExitCode.usage) }
    return (flags, rest)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage, code: ExitCode.usage) }
let rest = Array(arguments.dropFirst())

switch command {
case "list":
    let (flags, _) = parse(rest, allowedFlags: ["--json", "--processes"], positionals: 0)
    let groups = snapshot(includeUsage: true)
    let processes = flags.contains("--processes")
    if flags.contains("--json") { printJSON(groups, processes: processes) } else { printTable(groups, processes: processes) }

case "pause", "resume":
    let (_, positionals) = parse(rest, allowedFlags: [], positionals: 1)
    let group = resolve(positionals[0], in: snapshot(includeUsage: false))
    let pausing = command == "pause"
    if pausing ? group.state == .paused : group.state == .running {
        print("\(group.app.name) is already \(group.state.label)")
        exit(0)
    }
    send(SignalPlan(signal: pausing ? .stop : .continue, pids: group.processes.map(\.pid)))
    print("\(pausing ? "Paused" : "Resumed") \(group.app.name) (\(group.processes.count) processes)")

case "kill":
    let (_, positionals) = parse(rest, allowedFlags: [], positionals: 1)
    let group = resolve(positionals[0], in: snapshot(includeUsage: false))
    send(SignalPlan.kill(group))
    print("Killed \(group.app.name) (\(group.processes.count) processes)")

case "pause-all":
    let (flags, _) = parse(rest, allowedFlags: ["--include-frontmost"], positionals: 0)
    let all = snapshot(includeUsage: false)
    let spared = flags.contains("--include-frontmost") ? nil : Workspace.foregroundApplicationPid()
    let targets = all.filter { $0.app.pid != spared && $0.state != .paused }
    send(SignalPlan.stopAll(targets))
    var message = "Paused \(targets.count) apps"
    if let spared, let name = all.first(where: { $0.app.pid == spared })?.app.name {
        message += ", kept \(name) running"
    }
    print(message)

case "resume-all":
    _ = parse(rest, allowedFlags: [], positionals: 0)
    let targets = snapshot(includeUsage: false).filter { $0.state != .running }
    send(SignalPlan.continueAll(targets))
    print("Resumed \(targets.count) apps")

case "help", "--help", "-h":
    print(usage)

default:
    fail(usage, code: ExitCode.usage)
}
