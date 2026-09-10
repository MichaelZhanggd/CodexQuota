import AppKit
import SwiftUI
import QuotaCore

signal(SIGPIPE, SIG_IGN)
let args = CommandLine.arguments

if args.contains("--check-quota") {
    guard let path = AppModel.codexExecutable() else { fputs("Codex executable not found\n", stderr); exit(1) }
    let client = QuotaClient(executableURL: path)
    var finished = false, success = false
    client.onSnapshot = { snapshot in
        for bucket in snapshot.buckets {
            print("\(bucket.id): primary remaining=\(bucket.primary.map { String($0.remainingPercent) } ?? "unknown")%, secondary remaining=\(bucket.secondary.map { String($0.remainingPercent) } ?? "unknown")%")
        }
        print("reset credits=\(snapshot.availableResetCredits.map(String.init) ?? "unknown")")
        success = true; finished = true
    }
    client.onStatus = { message, _ in if let message { fputs(message + "\n", stderr); finished = true } }
    client.refresh()
    let deadline = Date().addingTimeInterval(25)
    while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    client.stop(); exit(success ? 0 : 1)
}

if args.contains("--check-windows") {
    _ = NSApplication.shared
    let tracker = WindowTracker(); tracker.poll()
    print("Codex running=\(tracker.running), active=\(tracker.active), windows=\(tracker.windows.count)")
    for window in tracker.windows { print("id=\(window.id) visible=\(window.visible) frame=\(window.frame)") }
    exit(0)
}

if let index = args.firstIndex(of: "--render-previews"), args.count > index + 1 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
    Task { @MainActor in
    do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "io.github.MichaelZhanggd.CodexQuota.preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    // Preview fixtures only. This path never runs during normal app startup.
    let reset = Date().timeIntervalSince1970 + 10860
    model.updatedAt = Date(); model.attachmentLabel = "已吸附"
    for (name, dark, compact, attached, primaryUsed, secondaryUsed) in [
        ("light", false, false, false, 20, 7),
        ("dark", true, false, false, 20, 7),
        ("compact-detached", true, true, false, 20, 7),
        ("compact-attached", true, true, true, 20, 7),
        ("compact-light", false, true, true, 20, 7),
        ("compact-warning-dark", true, true, true, 71, 81),
        ("compact-warning-light", false, true, true, 71, 81),
        ("compact-threshold", true, true, true, 70, 80),
        ("compact-weekly-warning", true, true, true, 70, 81)
    ] {
        model.snapshot = try QuotaSnapshot.decode(Data("{\"rateLimits\":{\"planType\":\"plus\",\"primary\":{\"usedPercent\":\(primaryUsed),\"windowDurationMins\":300,\"resetsAt\":\(reset)},\"secondary\":{\"usedPercent\":\(secondaryUsed),\"windowDurationMins\":10080,\"resetsAt\":\(reset + 500000)}},\"rateLimitResetCredits\":{\"availableCount\":2}}".utf8))
        model.compact = compact; model.appearance = dark ? "dark" : "light"
        model.isAttached = attached
        let view = QuotaView(model: model).environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: model.panelSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        if compact {
            @MainActor func quotaTooltipCount(_ view: NSView) -> Int {
                (view.toolTip?.contains("重置") == true ? 1 : 0)
                    + view.subviews.reduce(0) { $0 + quotaTooltipCount($1) }
            }
            guard quotaTooltipCount(host) >= 2 else {
                fputs("Missing native quota tooltips\n", stderr); exit(1)
            }
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
        print(directory.appendingPathComponent("\(name).png").path)
    }
    exit(0)
    } catch { fputs("Preview rendering failed: \(error)\n", stderr); exit(1) }
    }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
