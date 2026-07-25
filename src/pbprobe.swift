// pbprobe — zero-side-effect liveness probe for the macOS pasteboard server.
//
// Reads NSPasteboard.general.changeCount (a cheap mach IPC round-trip to
// pboard) on a background thread and waits up to <timeout> seconds for it
// to return. It never reads or writes clipboard *content*, so it cannot
// trigger a Universal Clipboard remote fetch.
//
// Exit codes:
//   0 — pasteboard server responded (healthy)
//   2 — no response within timeout (server hung)
//
// Usage: pbprobe [timeout-seconds]   (default 25)

import AppKit
import Foundation

let timeout: Double = {
    guard CommandLine.arguments.count > 1,
          let t = Double(CommandLine.arguments[1]), t > 0 else { return 25 }
    return t
}()

let sem = DispatchSemaphore(value: 0)

Thread.detachNewThread {
    _ = NSPasteboard.general.changeCount
    sem.signal()
}

// exit() terminates the whole process even if the probe thread is stuck
// inside a hung mach call, so no zombie probes accumulate.
exit(sem.wait(timeout: .now() + timeout) == .timedOut ? 2 : 0)
