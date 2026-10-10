import AppKit
import Foundation

/// Groups helper processes under their parent app using the process tree (spec 7.11, D12: public APIs only).
nonisolated enum Grouping {
    /// Walks up from `pid` (itself first) and returns the first PID that `isApp` accepts.
    /// Stops at PID 1 (launchd), at a missing parent and at a loop. nil = no parent app.
    static func parentApp(of pid: Int32, ppid: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        var seen = Set<Int32>()
        while current > 1, seen.insert(current).inserted {
            if isApp(current) { return current }
            guard let parent = ppid(current) else { return nil }
            current = parent
        }
        return nil
    }

    /// Parent PID from the kernel process table.
    static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// A regular app bundle that is not this mixer.
    /// ponytail: helpers (browser renderers, XPC services) are background-only, so they walk up to the app that started them.
    static func isApp(_ pid: Int32) -> Bool {
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular, app.bundleURL?.pathExtension == "app" else { return false }
        return true
    }
}
