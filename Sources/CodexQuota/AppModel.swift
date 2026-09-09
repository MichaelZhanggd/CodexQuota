import AppKit
import SwiftUI
import ServiceManagement
import QuotaCore

final class AppModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var updatedAt: Date?
    @Published var error: String?
    @Published var refreshing = false
    @Published var attachmentLabel = "等待 Codex 窗口"
    @Published var isAttached = false
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compact"); onLayout?() } }
    @Published var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "mode"); onLayout?() } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval"); scheduleRefresh() } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance"); onLayout?() } }
    @Published var selectedBucketID = "codex" { didSet { onData?() } }
    @Published var loginEnabled = false
    @Published var loginMessage: String?
    @Published var settingsOpen = false
    var onLayout: (() -> Void)?
    var onData: (() -> Void)?
    var onAttach: (() -> Void)?
    var onDetach: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let defaults: UserDefaults
    private var client: QuotaClient?
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        compact = defaults.bool(forKey: "compact")
        mode = DisplayMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .follow
        let saved = defaults.double(forKey: "interval")
        interval = [30, 60, 120, 300].contains(saved) ? saved : 60
        appearance = defaults.string(forKey: "appearance") ?? "system"
    }

    var bucket: QuotaBucket? {
        snapshot?.buckets.first(where: { $0.id == selectedBucketID }) ?? snapshot?.buckets.first
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : (appearance == "light" ? .light : nil) }
    var panelSize: CGSize { CGSize(width: 304, height: compact ? 46 : 344) }
    func toggleAttachment() {
        switch AttachmentToggleAction.next(isAttached: isAttached) {
        case .attach: onAttach?()
        case .detach: onDetach?()
        }
    }
    func isStale(at now: Date = Date()) -> Bool {
        guard let updatedAt else { return true }
        return error != nil || now.timeIntervalSince(updatedAt) > max(90, interval * 2)
    }

    func start() {
        guard let executable = Self.codexExecutable() else {
            error = "未找到 Codex，请先安装并登录 Codex 桌面应用。"; return
        }
        let client = QuotaClient(executableURL: executable)
        self.client = client
        client.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.snapshot = snapshot; self.updatedAt = Date(); self.error = nil; self.refreshing = false
            self.onData?()
        }
        client.onStatus = { [weak self] error, busy in
            guard let self else { return }
            self.refreshing = busy
            if let error { self.error = error }
            self.onData?()
        }
        refresh(); scheduleRefresh(); updateLoginStatus()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTimer?.invalidate(); self?.client?.stop()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(); self?.scheduleRefresh()
        })
    }

    func stop() {
        refreshTimer?.invalidate(); client?.stop()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
    }

    func refresh() { client?.refresh() }
    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        guard client != nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func updateLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval { loginMessage = "请在系统登录项中允许 Codex Quota。" }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
            updateLoginStatus()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginMessage = "设置未生效，请在系统设置 → 通用 → 登录项中管理。"
            updateLoginStatus()
        }
    }

    static func codexExecutable() -> URL? {
        let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        let candidates = [bundle?.appendingPathComponent("Contents/Resources/codex"),
                          URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
                          URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
