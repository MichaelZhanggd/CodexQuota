import AppKit
import QuotaCore

struct CodexWindow: Identifiable {
    let id: CGWindowID
    let frame: CGRect
    let visible: Bool
}

final class WindowTracker {
    private(set) var windows: [CodexWindow] = []
    private(set) var active = false
    private(set) var running = false
    private(set) var selectedID: CGWindowID?
    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private var lastPoll = Date.distantPast
    private var pid: pid_t?

    var selected: CodexWindow? { windows.first { $0.id == selectedID } }

    func start() {
        poll()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let interval = self.active && NSEvent.pressedMouseButtons != 0 ? 0.05 : (self.active ? 0.25 : 0.8)
            guard Date().timeIntervalSince(self.lastPoll) >= interval else { return }
            self.poll()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }
    func select(_ window: CodexWindow) { selectedID = window.id; onUpdate?() }

    func poll() {
        lastPoll = Date()
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first
        running = app != nil
        active = app?.isActive == true
        guard let app else {
            windows = []; selectedID = nil; pid = nil; onUpdate?(); return
        }
        if pid != app.processIdentifier { selectedID = nil; pid = app.processIdentifier }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        windows = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cg = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cg.width >= 400, cg.height >= 250 else { return nil }
            let rect = CGRect(x: cg.minX, y: mainHeight - cg.maxY, width: cg.width, height: cg.height)
            return CodexWindow(id: id, frame: rect,
                               visible: !app.isHidden && (info[kCGWindowIsOnscreen as String] as? Bool == true))
        }
        if selectedID == nil { selectedID = (windows.first(where: \.visible) ?? windows.first)?.id }
        // A missing bound window is not silently replaced by a different task window.
        onUpdate?()
    }

    static func screen(for rect: CGRect) -> CGRect {
        (NSScreen.screens.max { a, b in
            let ai = a.frame.intersection(rect), bi = b.frame.intersection(rect)
            return max(0, ai.width) * max(0, ai.height) < max(0, bi.width) * max(0, bi.height)
        } ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
