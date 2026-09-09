import Foundation

/// Owned and invoked by the main thread; results are also delivered on the main queue.
public final class QuotaClient {
    public var onSnapshot: ((QuotaSnapshot) -> Void)?
    public var onStatus: ((String?, Bool) -> Void)?
    public var isRunning: Bool { process?.isRunning == true }
    private let executableURL: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var ready = false
    private var pendingID: Int?
    private var nextID = 2
    private var deadline: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var failures = 0
    private var lastSnapshot: QuotaSnapshot?

    public init(executableURL: URL, arguments: [String] = ["app-server", "--stdio"], timeout: TimeInterval = 20) {
        self.executableURL = executableURL; self.arguments = arguments; self.timeout = timeout
    }

    public func refresh() {
        retry?.cancel(); retry = nil
        guard pendingID == nil else { return }
        onStatus?(nil, true)
        if !isRunning { launch(); return }
        guard ready else { return }
        let id = nextID; nextID += 1; pendingID = id
        armTimeout()
        send(["id": id, "method": "account/rateLimits/read", "params": [:]])
    }

    private func launch() {
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = executableURL; p.arguments = arguments
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        process = p; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        ready = false; buffer.removeAll(); pendingID = 1
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak p] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.receive(data)
            }
        }
        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.process === process else { return }
                self.fail("Codex 连接已中断，正在重连。")
            }
        }
        do { try p.run() } catch { fail("无法启动 Codex，请检查桌面应用是否已安装。") ; return }
        armTimeout()
        send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_quota", "title": "Codex Quota", "version": "1.0.0"]]])
    }

    private func send(_ object: [String: Any]) {
        guard let input else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.write(contentsOf: data)
        } catch { fail("无法连接 Codex，正在重试。") }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 2_097_152 else { fail("Codex 返回的数据过大，请更新 Codex 后重试。"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                fail("Codex 返回格式无法识别，请更新 Codex 后重试。"); return
            }
            if let id = message["id"] as? Int, id == pendingID {
                deadline?.cancel(); deadline = nil; pendingID = nil
                if message["error"] != nil { fail("暂时无法读取额度，请确认 Codex 已登录且网络可用。"); return }
                if id == 1 {
                    ready = true; send(["method": "initialized"]); refresh()
                } else if let result = message["result"] as? [String: Any] {
                    accept(result, partial: false)
                } else { fail("未收到有效额度数据，正在重试。"); return }
            } else if message["method"] as? String == "account/rateLimits/updated",
                      let params = message["params"] as? [String: Any] {
                accept(params, partial: true)
            }
        }
    }

    private func accept(_ object: [String: Any], partial: Bool) {
        do {
            var snapshot = try QuotaSnapshot.decode(JSONSerialization.data(withJSONObject: object))
            if partial, let previous = lastSnapshot {
                let updatedIDs = Set(snapshot.buckets.map(\.id))
                snapshot = QuotaSnapshot(buckets: (previous.buckets.filter { !updatedIDs.contains($0.id) } + snapshot.buckets).sorted {
                    if $0.id == "codex" { return $1.id != "codex" }
                    if $1.id == "codex" { return false }
                    return $0.id < $1.id
                }, availableResetCredits: snapshot.availableResetCredits ?? previous.availableResetCredits)
            }
            lastSnapshot = snapshot; failures = 0
            onStatus?(nil, pendingID != nil); onSnapshot?(snapshot)
        } catch {
            if !partial { fail("当前登录方式没有可用的订阅额度，请在 Codex 中检查账号。") }
        }
    }

    private func armTimeout() {
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fail("读取额度超时，正在重试。") }
        deadline = work; DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func fail(_ message: String) {
        stop()
        onStatus?(message, false)
        failures = min(failures + 1, 7)
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(300, 5 * pow(2, Double(failures - 1))), execute: work)
    }

    public func stop() {
        retry?.cancel(); retry = nil; deadline?.cancel(); deadline = nil
        let old = process; process = nil; pendingID = nil; ready = false
        output?.readabilityHandler = nil; output = nil
        try? input?.close(); input = nil
        buffer.removeAll(); old?.terminationHandler = nil
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if old.isRunning { kill(old.processIdentifier, SIGKILL) }
            }
        }
    }

    deinit { stop() }
}
