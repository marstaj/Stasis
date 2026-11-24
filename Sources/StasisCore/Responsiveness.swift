import ApplicationServices
import Foundation
import os

public enum Responsiveness {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias IsUnresponsive = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    private typealias SerialNumberForPid = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private struct Calls {
        let connection: Int32
        let isUnresponsive: IsUnresponsive
        let serialNumberForPid: SerialNumberForPid
    }

    /// There is no public API for this verdict, so the SkyLight and Carbon symbols behind it are
    /// looked up at run time: a macOS that drops one disables the check instead of failing to
    /// launch. Nil also when there is no WindowServer session (the CLI over SSH).
    private static let calls: Calls? = {
        let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "responsiveness")
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            let pointer = dlsym(defaultHandle, name)
            if pointer == nil {
                logger.error("\(name, privacy: .public) is unavailable; apps will never show as not responding")
            }
            return pointer
        }
        guard let connection = symbol("CGSMainConnectionID"),
              let isUnresponsive = symbol("CGSEventIsAppUnresponsive"),
              let serialNumberForPid = symbol("GetProcessForPID") else { return nil }
        let id = unsafeBitCast(connection, to: MainConnection.self)()
        guard id != 0 else {
            logger.error("No WindowServer connection; apps will never show as not responding")
            return nil
        }
        return Calls(
            connection: id,
            isUnresponsive: unsafeBitCast(isUnresponsive, to: IsUnresponsive.self),
            serialNumberForPid: unsafeBitCast(serialNumberForPid, to: SerialNumberForPid.self)
        )
    }()

    /// WindowServer's own "Not Responding" verdict, also true for a stopped app. False when the
    /// check is unavailable or the pid has no serial number (the app has just exited).
    public static func isUnresponsive(pid: pid_t) -> Bool {
        guard let calls else { return false }
        var serialNumber = ProcessSerialNumber()
        guard calls.serialNumberForPid(pid, &serialNumber) == noErr else { return false }
        return calls.isUnresponsive(calls.connection, &serialNumber)
    }
}
