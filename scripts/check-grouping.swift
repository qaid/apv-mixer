// Run: swiftc TurntableMixer/Grouping.swift scripts/check-grouping.swift -o /tmp/check-grouping && /tmp/check-grouping
import Foundation

@main struct CheckGrouping {
    static func main() {
        // 1 (launchd) <- 100 (app) <- 200 (helper) <- 300 (renderer); 400 <- 1 is a lone daemon
        let parents: [Int32: Int32] = [100: 1, 200: 100, 300: 200, 400: 1]
        let ppid: (Int32) -> Int32? = { parents[$0] }
        let apps: Set<Int32> = [100]
        let isApp: (Int32) -> Bool = { apps.contains($0) }

        assert(Grouping.parentApp(of: 100, ppid: ppid, isApp: isApp) == 100, "an app is its own parent app")
        assert(Grouping.parentApp(of: 200, ppid: ppid, isApp: isApp) == 100, "helper groups under the app")
        assert(Grouping.parentApp(of: 300, ppid: ppid, isApp: isApp) == 100, "nested helper groups under the app")
        assert(Grouping.parentApp(of: 400, ppid: ppid, isApp: isApp) == nil, "no parent app")
        assert(Grouping.parentApp(of: 999, ppid: ppid, isApp: isApp) == nil, "unknown pid")
        assert(Grouping.parentApp(of: 1, ppid: ppid, isApp: { _ in true }) == nil, "never PID 1")
        assert(Grouping.parentApp(of: 0, ppid: ppid, isApp: { _ in true }) == nil, "never PID 0")

        // a loop terminates
        let loop: [Int32: Int32] = [10: 20, 20: 30, 30: 10]
        assert(Grouping.parentApp(of: 10, ppid: { loop[$0] }, isApp: { _ in false }) == nil, "loop ends")

        // the walk stops at the first app, not the last
        let two: [Int32: Int32] = [500: 1, 600: 500, 700: 600]
        assert(Grouping.parentApp(of: 700, ppid: { two[$0] }, isApp: { $0 == 600 || $0 == 500 }) == 600, "nearest app wins")
        print("check-grouping: all checks passed")
    }
}
