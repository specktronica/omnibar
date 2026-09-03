import AppKit
import Foundation

enum AppRelaunch {
    private(set) static var isInProgress = false

    static func perform() {
        guard !isInProgress else { return }
        isInProgress = true
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", waitThenOpenScript(pid: pid, bundlePath: bundlePath)]
        do {
            try task.run()
        } catch {
            isInProgress = false
            return
        }
        NSApp.terminate(nil)
    }

    static func waitThenOpenScript(pid: Int32, bundlePath: String) -> String {
        """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done
        exec /usr/bin/open \(shellQuoted(bundlePath))
        """
    }

    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
