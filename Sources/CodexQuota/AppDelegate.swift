import AppKit
import Carbon
import SwiftUI
import QuotaCore

final class QuotaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    let tracker = WindowTracker()
    private var panel: QuotaPanel!
    private var statusItem: NSStatusItem!
    private var attachment: Attachment?
    private var wantsAttachment = true
    private var dragging = false
    private var dismissed = false
    private var peekUntil = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        signal(SIGPIPE, SIG_IGN)
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.MichaelZhanggd.CodexQuota").count > 1 {
            NSApp.terminate(nil); return
        }
        loadAttachment()
        panel = QuotaPanel(contentRect: CGRect(origin: .zero, size: model.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex Quota"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuotaView(model: model))
        restoreFrame()
        model.onLayout = { [weak self] in self?.layoutPanel() }
        model.onData = { [weak self] in self?.updateStatusItem() }
        model.onAttach = { [weak self] in self?.attachToCurrent() }
        model.onDetach = { [weak self] in self?.detach() }
        model.onDismiss = { [weak self] in self?.dismissed = true; self?.panel.orderOut(nil) }
        model.onDragStart = { [weak self] in self?.dragging = true }
        model.onDragEnd = { [weak self] in self?.endDrag() }
        createStatusItem()
        tracker.onUpdate = { [weak self] in self?.updatePanel() }
        tracker.start()
        model.start()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tracker.poll() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.panel.setFrame(Attachment.fit(self.panel.frame, in: WindowTracker.screen(for: self.panel.frame)), display: true)
            self.tracker.poll()
        })
        layoutPanel()
        // Launch is an explicit request to see the app; login startup remains unobtrusive.
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !CommandLine.arguments.contains("--background") && !loginLaunch { reveal() }
    }

    private func loadAttachment() {
        let defaults = UserDefaults.standard
        wantsAttachment = defaults.object(forKey: "wantsAttachment") == nil || defaults.bool(forKey: "wantsAttachment")
        if let data = defaults.data(forKey: "attachment") { attachment = try? JSONDecoder().decode(Attachment.self, from: data) }
        if wantsAttachment && attachment == nil { attachment = Attachment(edge: .right, offset: 16) }
        model.isAttached = wantsAttachment && attachment != nil
    }

    private func saveAttachment() {
        UserDefaults.standard.set(wantsAttachment, forKey: "wantsAttachment")
        UserDefaults.standard.set(attachment.flatMap { try? JSONEncoder().encode($0) }, forKey: "attachment")
    }

    private func restoreFrame() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = CGRect(x: screen.maxX - model.panelSize.width - 24, y: screen.maxY - model.panelSize.height - 24,
                           width: model.panelSize.width, height: model.panelSize.height)
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            let old = NSRectFromString(saved)
            if old.width > 0, old.origin.x.isFinite, old.origin.y.isFinite {
                frame.origin = CGPoint(x: old.minX, y: old.maxY - frame.height)
            }
        }
        panel.setFrame(Attachment.fit(frame, in: WindowTracker.screen(for: frame)), display: false)
    }

    private func layoutPanel() {
        guard panel != nil else { return }
        let old = panel.frame
        panel.setFrame(Attachment.resized(old, to: model.panelSize, screen: WindowTracker.screen(for: old)), display: true)
        panel.appearance = model.appearance == "dark" ? NSAppearance(named: .darkAqua) : (model.appearance == "light" ? NSAppearance(named: .aqua) : nil)
        panel.level = model.mode == .normal ? .normal : .floating
        updatePanel(); updateStatusItem()
    }

    private func updatePanel() {
        guard panel != nil, !dragging else { return }
        let target = tracker.selected
        if wantsAttachment, let attachment, let target, target.visible {
            let frame = attachment.frame(target: target.frame, size: model.panelSize, screen: WindowTracker.screen(for: target.frame))
            if frame != panel.frame { panel.setFrame(frame, display: true) }
        }
        let label: String
        if !tracker.running { label = "Codex 未运行" }
        else if target == nil { label = "请选择 Codex 窗口" }
        else if !wantsAttachment { label = "自由位置" }
        else { label = target?.visible == true ? "已吸附" : "窗口已收起" }
        if model.attachmentLabel != label { model.attachmentLabel = label }
        let interacting = model.settingsOpen && target?.visible == true
        let show = !dismissed && (model.mode.shouldShow(targetVisible: target?.visible == true, targetActive: tracker.active) || Date() < peekUntil || interacting)
        if show {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible { panel.orderOut(nil) }
    }

    private func endDrag() {
        dismissed = false
        tracker.poll()
        let match = tracker.windows.filter(\.visible).compactMap { window -> (CodexWindow, Attachment, CGFloat)? in
            guard let attachment = Attachment.snap(panel: panel.frame, target: window.frame, screen: WindowTracker.screen(for: window.frame)) else { return nil }
            let snapped = attachment.frame(target: window.frame, size: model.panelSize, screen: WindowTracker.screen(for: window.frame))
            return (window, attachment, hypot(snapped.minX - panel.frame.minX, snapped.minY - panel.frame.minY))
        }.min { $0.2 < $1.2 }
        if let match {
            attachment = match.1; wantsAttachment = true; tracker.select(match.0)
        } else { attachment = nil; wantsAttachment = false }
        model.isAttached = wantsAttachment
        dragging = false
        saveAttachment()
        panel.setFrame(Attachment.fit(panel.frame, in: WindowTracker.screen(for: panel.frame)), display: true)
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
        updatePanel()
    }

    private func attachToCurrent() {
        tracker.poll()
        guard let target = tracker.windows.first(where: \.visible) ?? tracker.windows.first else { return }
        attachment = Attachment(edge: .right, offset: 16); wantsAttachment = true
        model.isAttached = true
        tracker.select(target); saveAttachment(); updatePanel()
    }

    private func detach() {
        if let attachment, let target = tracker.selected {
            let screen = WindowTracker.screen(for: target.frame)
            panel.setFrame(attachment.detachedFrame(from: panel.frame, target: target.frame, screen: screen), display: true)
        }
        wantsAttachment = false; attachment = nil; model.isAttached = false
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
        saveAttachment(); updatePanel()
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard statusItem != nil else { return }
        let value = model.bucket?.primary?.remainingPercent
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Codex 额度")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.title = " \(value.map { "\($0)%" } ?? "—")\(model.isStale() ? " ·" : "")"
        statusItem.button?.toolTip = "Codex 剩余额度 · 点击展开 · 右键设置"
    }

    @objc private func statusClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for mode in DisplayMode.allCases {
                let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = mode.rawValue; item.state = model.mode == mode ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let items: [(String, Selector)] = [("显示额度", #selector(reveal)), ("立即刷新", #selector(refresh)), ("退出 Codex Quota", #selector(quit))]
            for (title, action) in items { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
            statusItem.menu = menu; sender.performClick(nil); statusItem.menu = nil
        } else { reveal() }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) { model.mode = mode; reveal() }
    }
    @objc private func refresh() { model.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func reveal() {
        dismissed = false; peekUntil = Date().addingTimeInterval(12)
        updatePanel(); panel.orderFrontRegardless()
    }

    func windowDidResignKey(_ notification: Notification) { updatePanel() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reveal(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let panel { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame") }
        model.stop(); tracker.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
