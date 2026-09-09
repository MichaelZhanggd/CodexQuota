// Live, reversible smoke check. Briefly hides/unhides Codex and restarts only Codex Quota.
// Run after installing: xcrun swift scripts/check-window-lifecycle.swift
import AppKit

let quotaID = "io.github.MichaelZhanggd.CodexQuota"
let appPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex Quota.app").path
let defaults = UserDefaults(suiteName: quotaID)!
let codex = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first!
let foreground = NSWorkspace.shared.frontmostApplication
let wasHidden = codex.isHidden
var savedPreferences: [String: Any]?

func waitUntil(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return condition()
}

func stopQuota() {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: quotaID) {
        app.terminate()
        if !waitUntil({ app.isTerminated }) { app.forceTerminate() }
    }
}

func launchQuota(background: Bool) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-g", appPath] + (background ? ["--args", "--background"] : [])
    try p.run(); p.waitUntilExit()
    guard waitUntil({ !NSRunningApplication.runningApplications(withBundleIdentifier: quotaID).isEmpty }) else {
        throw NSError(domain: "QuotaSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "App did not launch"])
    }
}

func panelVisible() -> Bool {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: quotaID).first else { return false }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return rect.width >= 250 && rect.width <= 310 && rect.height >= 40 && rect.height <= 350
    }
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw NSError(domain: "QuotaSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
    print("PASS:", message)
}

func runChecks() throws {
    stopQuota()
    savedPreferences = defaults.persistentDomain(forName: quotaID)
    defer {
        stopQuota()
        if let savedPreferences { defaults.setPersistentDomain(savedPreferences, forName: quotaID) }
        else { defaults.removePersistentDomain(forName: quotaID) }
        defaults.synchronize()
        if wasHidden { codex.hide() } else { codex.unhide() }
        foreground?.activate(options: [])
        try? launchQuota(background: false)
    }
    for mode in ["follow", "always"] {
        stopQuota()
        defaults.set(mode, forKey: "mode"); defaults.set(false, forKey: "compact")
        defaults.set(true, forKey: "wantsAttachment"); defaults.synchronize()
        codex.unhide(); codex.activate(options: [])
        try launchQuota(background: true)
        try require(waitUntil { panelVisible() }, "\(mode): visible when Codex is foreground")
        codex.hide()
        try require(waitUntil { codex.isHidden }, "Codex hidden")
        if mode == "follow" {
            try require(waitUntil { !panelVisible() }, "follow: panel hides with Codex")
        } else {
            // Wait past the window tracking interval before asserting persistent visibility.
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            try require(panelVisible(), "always: panel stays visible while Codex is hidden")
        }
        codex.unhide(); codex.activate(options: [])
        try require(waitUntil { panelVisible() }, "\(mode): panel visible after Codex returns")
    }
}

do { try runChecks(); print("Window lifecycle checks passed; preferences and foreground restored.") }
catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
