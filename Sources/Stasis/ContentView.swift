import AppKit
import StasisCore
import ServiceManagement
import SwiftUI
import os

struct ContentView: View {
    let monitor: ProcessMonitor
    let updates: UpdateChecker
    @AppStorage("sortOrder") private var sortOrder = AppSortOrder.name
    @AppStorage("appFilter") private var filter = AppFilter.all
    @AppStorage("pausedFirst") private var pausedFirst = false

    var body: some View {
        let visible = filter.filtered(monitor.groups)
        VStack(spacing: 0) {
            if monitor.groups.isEmpty {
                Text("No running apps")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 8) {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(AppSortOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Picker("Show", selection: $filter) {
                            ForEach(AppFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Paused first", isOn: $pausedFirst)
                            .toggleStyle(.checkbox)
                            .fixedSize()
                    }
                    HStack {
                        if let front = monitor.frontApp, filter.includes(front) {
                            Button("Pause All Except \(front.name)") { monitor.pauseAll(sparingFrontApp: true, filter: filter) }
                                .disabled(monitor.pauseAllTargets(sparingFrontApp: true, filter: filter).isEmpty)
                                .lineLimit(1)
                        }
                        Button("Pause All") { monitor.pauseAll(sparingFrontApp: false, filter: filter) }
                            .disabled(monitor.pauseAllTargets(sparingFrontApp: false, filter: filter).isEmpty)
                            .fixedSize()
                        Spacer()
                        Button("Resume All") { monitor.resumeAll(filter: filter) }
                            .disabled(!visible.contains { $0.state != .running })
                            .fixedSize()
                    }
                    let hidden = filter.hiddenNotRunning(in: monitor.groups).count
                    if hidden > 0, let other = filter.complement {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text(hidden == 1
                                ? "1 paused \(other.kindName) app is hidden"
                                : "\(hidden) paused \(other.kindName) apps are hidden")
                            Spacer()
                            Button("Show") { filter = other }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
                if visible.isEmpty {
                    Text(filter.emptyListText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    // fixedSize makes the ScrollView take its ideal height (its content height) instead
                    // of the near-zero height the popover proposes; the frame caps it.
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(
                                sortOrder.sorted(visible, pausedFirst: pausedFirst, cpuRate: monitor.cpuRate),
                                id: \.app.pid
                            ) { group in
                                AppRow(group: group, monitor: monitor)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 520)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            footer
        }
        .frame(width: 385)
        .onAppear { monitor.setPopoverVisible(true) }
        .onDisappear { monitor.setPopoverVisible(false) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = monitor.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                LaunchAtLoginToggle()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            if let current = UpdateChecker.currentVersion {
                HStack {
                    Text("Version \(current)").foregroundStyle(.secondary)
                    Spacer()
                    if let version = updates.availableVersion {
                        Link("Stasis \(version) is available", destination: UpdateChecker.releasePage)
                    }
                }
                .font(.caption)
            }
        }
        .padding(10)
    }
}

private extension AppSortOrder {
    var title: String {
        switch self {
        case .name: "Name"
        case .memory: "Memory"
        case .cpu: "CPU"
        }
    }
}

private extension AppFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .dock: "Dock"
        case .menuBar: "Menu Bar"
        }
    }

    var kindName: String {
        switch self {
        case .all: "running"
        case .dock: "Dock"
        case .menuBar: "menu bar"
        }
    }

    var emptyListText: String { "No \(kindName) apps" }
}

private struct AppRow: View {
    let group: AppGroup
    let monitor: ProcessMonitor
    @State private var expanded = false
    /// Measured height of the name and state lines; the icon is drawn as a square of this side.
    @State private var labelHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14)
                    .padding(.horizontal, 8)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let icon = monitor.icons[group.app.pid] {
                        Image(nsImage: icon).resizable().frame(width: labelHeight, height: labelHeight)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.app.name).fontWeight(.medium).lineLimit(1)
                        StateLabel(group: group)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { labelHeight = $0 }
                    Spacer(minLength: 8)
                    UsageColumn(bytes: group.totalResidentBytes, cpuRate: monitor.cpuRate(of: group))
                    ToggleButton(isStopped: group.state != .running) { monitor.toggle(group) }
                    KillButton { monitor.forceQuit(group) }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            // The buttons take their own clicks. Not animated: an animated size change leaves the
            // menu bar panel at its expanded height after collapsing.
            .onTapGesture { expanded.toggle() }

            if expanded {
                VStack(spacing: 2) {
                    ForEach(group.processes, id: \.pid) { process in
                        ProcessRow(
                            process: process, cpuRate: monitor.cpuRates[process.pid],
                            toggle: { monitor.toggle(process) }, kill: { monitor.forceQuit(process) }
                        )
                    }
                }
                .padding(.leading, 46)
                .padding(.trailing, 8)
                .padding(.top, 2)
            }
        }
    }

    private var rowBackground: Color {
        switch group.state {
        case .running: .clear
        case .notResponding: .red.opacity(0.15)
        case .partiallyPaused: .yellow.opacity(0.15)
        case .paused: .orange.opacity(0.2)
        }
    }
}

private struct StateLabel: View {
    let group: AppGroup

    var body: some View {
        switch group.state {
        case .running:
            Text("Running").font(.caption).foregroundStyle(.secondary)
        case .notResponding:
            stateLabel("Not Responding", systemImage: "exclamationmark.triangle.fill")
        case .partiallyPaused:
            stateLabel("\(group.stoppedCount) of \(group.processes.count) paused")
        case .paused:
            stateLabel("Paused")
        }
    }

    /// Untinted: the row's own colour is unreadable on its background of the same colour.
    private func stateLabel(_ text: String, systemImage: String = "pause.fill") -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
    }
}

private struct ProcessRow: View {
    let process: ProcessRecord
    let cpuRate: Double?
    let toggle: () -> Void
    let kill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name).lineLimit(1)
            Text(String(process.pid)).foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            UsageColumn(bytes: process.residentBytes, cpuRate: cpuRate)
            ToggleButton(isStopped: process.isStopped, compact: true, action: toggle)
            KillButton(compact: true, action: kill)
        }
        .font(.caption)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            process.isStopped ? Color.orange.opacity(0.2) : .clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

private struct UsageColumn: View {
    let bytes: UInt64
    let cpuRate: Double?

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Self.formatter.string(fromByteCount: Int64(bytes)))
                .monospacedDigit()
            Text(cpuRate.map { String(format: "%.1f%% CPU", $0) } ?? "— CPU")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minWidth: 66, alignment: .trailing)
    }
}

/// The whole filled rectangle is the click target.
private struct RowButtonStyle: ButtonStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: compact ? 28 : 34, height: compact ? 20 : 28)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.22 : 0.1),
                in: RoundedRectangle(cornerRadius: compact ? 4 : 6)
            )
            .contentShape(Rectangle())
    }
}

private struct ToggleButton: View {
    let isStopped: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isStopped ? "play.fill" : "pause.fill")
        }
        .buttonStyle(RowButtonStyle(compact: compact))
        .help(isStopped ? "Resume" : "Pause")
    }
}

private struct KillButton: View {
    var compact = false
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed { action() }
            armed.toggle()
        } label: {
            Image(systemName: armed ? "xmark.circle.fill" : "xmark.circle")
                .foregroundStyle(armed ? Color.red : Color.secondary)
        }
        .buttonStyle(RowButtonStyle(compact: compact))
        .help(armed ? "Click again to kill" : "Kill")
        // Killing loses unsaved work and sits next to the pause button, so it takes two clicks;
        // moving the pointer away disarms it.
        .onHover { if !$0 { armed = false } }
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    private let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "login-item")

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Launch at login", isOn: $enabled)
                .toggleStyle(.checkbox)
                .onChange(of: enabled) { _, newValue in apply(newValue) }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private func apply(_ enable: Bool) {
        // Resetting the toggle after a failure re-fires onChange; that must not retry and overwrite the error.
        guard enable != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            logger.error("Launch-at-login change failed: \(error.localizedDescription)")
            self.error = "Launch at login failed: \(error.localizedDescription). Run the installed .app bundle."
            enabled = SMAppService.mainApp.status == .enabled
        }
    }
}
