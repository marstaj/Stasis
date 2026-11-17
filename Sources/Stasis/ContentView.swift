import AppKit
import StasisCore
import ServiceManagement
import SwiftUI
import os

struct ContentView: View {
    let monitor: ProcessMonitor

    var body: some View {
        VStack(spacing: 0) {
            if monitor.groups.isEmpty {
                Text("No running apps")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // fixedSize makes the ScrollView take its ideal height (its content height) instead
                // of the near-zero height the popover proposes; the frame caps it.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(monitor.groups, id: \.app.pid) { group in
                            AppRow(group: group, monitor: monitor)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: 400)
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
        }
        .padding(10)
    }
}

private struct AppRow: View {
    let group: AppGroup
    let monitor: ProcessMonitor
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Two click zones: left of the icon expands, the icon and everything right of it toggles.
            HStack(spacing: 0) {
                // Not animated: an animated size change leaves the menu bar panel at its
                // expanded height after collapsing.
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let icon = monitor.icons[group.app.pid] {
                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.app.name).fontWeight(.medium).lineLimit(1)
                        StateLabel(group: group)
                    }
                    Spacer(minLength: 8)
                    UsageColumn(bytes: group.totalResidentBytes, cpuRate: monitor.cpuRate(of: group))
                    ToggleButton(isStopped: group.state != .running) { monitor.toggle(group) }
                    KillButton { monitor.forceQuit(group) }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .onTapGesture { monitor.toggle(group) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))

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
        case .partiallyPaused:
            Label("\(group.stoppedCount) of \(group.processes.count) processes paused", systemImage: "pause")
                .font(.caption).foregroundStyle(.yellow)
        case .paused:
            Label("Paused", systemImage: "pause.fill")
                .font(.caption).foregroundStyle(.orange)
        }
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
            ToggleButton(isStopped: process.isStopped, action: toggle)
            KillButton(action: kill)
        }
        .font(.caption)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            process.isStopped ? Color.orange.opacity(0.2) : .clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
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
        .frame(minWidth: 72, alignment: .trailing)
    }
}

private struct ToggleButton: View {
    let isStopped: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isStopped ? "play.fill" : "pause.fill")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(isStopped ? "Resume" : "Pause")
    }
}

private struct KillButton: View {
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed { action() }
            armed.toggle()
        } label: {
            Image(systemName: armed ? "xmark.circle.fill" : "xmark.circle")
                .foregroundStyle(armed ? Color.red : Color.secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
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
