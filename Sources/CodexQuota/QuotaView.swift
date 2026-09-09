import AppKit
import SwiftUI
import ServiceManagement
import QuotaCore

private struct DragHandle: NSViewRepresentable {
    let start: () -> Void
    let end: () -> Void
    func makeNSView(context: Context) -> Handle { let view = Handle(); view.start = start; view.end = end; return view }
    func updateNSView(_ nsView: Handle, context: Context) { nsView.start = start; nsView.end = end }
    final class Handle: NSView {
        var start: (() -> Void)?
        var end: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            start?(); NSCursor.closedHand.push(); window?.performDrag(with: event); NSCursor.pop(); end?()
        }
    }
}

struct QuotaView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { scheme == .dark ? Color(white: 0.91) : Color(white: 0.16) }
    private var surface: Color { scheme == .dark ? Color(white: 0.115) : Color(white: 0.975) }
    private var secondary: Color { scheme == .dark ? Color(white: 0.57) : Color(white: 0.48) }

    var body: some View {
        Group {
            if model.compact { mini } else { expanded }
        }
        .foregroundStyle(ink)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: model.compact ? 12 : 20))
        .overlay(RoundedRectangle(cornerRadius: model.compact ? 12 : 20).strokeBorder(ink.opacity(0.1), lineWidth: 1))
        .preferredColorScheme(model.colorScheme)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                dragTitle
                toolButton("minus", help: "折叠为迷你条") { model.compact = true }
                toolButton("slider.horizontal.3", help: "组件设置") { model.settingsOpen.toggle() }
                    .popover(isPresented: $model.settingsOpen, arrowEdge: .bottom) { settings }
            }
            .frame(height: 34)
            .padding(.bottom, 21)

            HStack {
                Text("剩余额度").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                Spacer()
                if (model.snapshot?.buckets.count ?? 0) > 1 {
                    Menu(model.bucket?.limitName ?? model.bucket?.id ?? "Codex") {
                        ForEach(model.snapshot?.buckets ?? []) { bucket in
                            Button(bucket.limitName ?? bucket.id) { model.selectedBucketID = bucket.id }
                        }
                    }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
                } else {
                    Text(model.bucket?.planType?.uppercased() ?? "CODEX")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(ink.opacity(0.05), in: Capsule()).foregroundStyle(secondary)
                }
            }
            .padding(.bottom, 14)

            quotaRow(model.bucket?.primary, fallback: "5 小时")
            Rectangle().fill(ink.opacity(0.07)).frame(height: 1).padding(.vertical, 15)
            quotaRow(model.bucket?.secondary, fallback: "每周")
            Spacer(minLength: 10)
            footer
            Rectangle().fill(ink.opacity(0.07)).frame(height: 1).padding(.top, 11).padding(.bottom, 10)
            HStack(spacing: 5) {
                Image(systemName: model.mode.symbol).font(.system(size: 10))
                Text(model.mode.title).font(.system(size: 10, weight: .medium))
                Spacer(minLength: 4)
                Text(model.attachmentLabel).font(.system(size: 9)).lineLimit(1)
            }.foregroundStyle(secondary)
        }
        .padding(18)
        .frame(width: 304, height: 344)
    }

    private var dragTitle: some View {
        DragHandle(start: { model.onDragStart?() }, end: { model.onDragEnd?() })
            .overlay(alignment: .leading) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(ink.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex").font(.system(size: 14, weight: .semibold))
                        Text("QUOTA").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(secondary)
                    }
                }.allowsHitTesting(false)
            }
            .help("拖动组件 · 靠近 Codex 边缘松手即可吸附")
            .accessibilityLabel("拖动额度组件")
    }

    private func quotaRow(_ window: QuotaWindow?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(window?.title ?? fallback).font(.system(size: 12, weight: .medium))
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(window?.resetText(now: context.date) ?? "暂无额度数据")
                            .font(.system(size: 10)).foregroundStyle(secondary)
                    }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(window.map { String($0.remainingPercent) } ?? "—")
                        .font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
                }
                .foregroundStyle(window.map { $0.remainingPercent <= 10 } == true ? Color.orange : ink)
            }
            GeometryReader { proxy in
                Capsule().fill(ink.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(window.map { $0.remainingPercent <= 10 } == true ? Color.orange.opacity(0.8) : ink.opacity(0.8))
                            .frame(width: proxy.size.width * Double(window?.remainingPercent ?? 0) / 100)
                    }
            }.frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let stale = model.isStale(at: context.date)
                HStack(spacing: 5) {
                    Circle().fill(stale ? Color.orange.opacity(0.8) : Color(red: 0.42, green: 0.60, blue: 0.49)).frame(width: 4, height: 4)
                    Text(statusText(at: context.date)).font(.system(size: 9)).foregroundStyle(secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Label(model.snapshot?.availableResetCredits.map { "重置卡 \($0) 张" } ?? "重置卡 —", systemImage: "arrow.counterclockwise.circle")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondary)
                .help("当前账号可用的额度重置卡数量")
            toolButton("arrow.clockwise", help: "立即刷新额度") { model.refresh() }.disabled(model.refreshing)
        }.frame(height: 17)
        .help(model.error ?? "从 Codex 读取真实账号额度；自动刷新不会发送 AI 对话。")
    }

    private func statusText(at now: Date) -> String {
        if model.refreshing { return "正在同步…" }
        if model.error != nil { return model.updatedAt == nil ? "连接失败 · 点击设置查看" : "数据已过期 · 等待重连" }
        guard let date = model.updatedAt else { return "连接 Codex…" }
        if model.isStale(at: now) { return "数据已过期 · 等待刷新" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return seconds < 60 ? "\(seconds) 秒前更新" : "\(seconds / 60) 分钟前更新"
    }

    private var mini: some View {
        ZStack {
            HStack(spacing: 0) {
                DragHandle(start: { model.onDragStart?() }, end: { model.onDragEnd?() })
                    .overlay {
                        Image(systemName: "terminal").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondary).allowsHitTesting(false)
                    }
                    .frame(width: 24, height: 30).help("拖动吸附到 Codex")
                DragHandle(start: { model.onDragStart?() }, end: { model.onDragEnd?() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .help("拖动吸附到 Codex")
                HStack(spacing: 2) {
                    Button { model.toggleAttachment() } label: {
                        Image(systemName: model.isAttached ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.isAttached ? ink.opacity(0.85) : secondary)
                    .help(model.isAttached ? "已吸附当前 Codex，点击解除" : "自由位置，点击吸附当前 Codex")
                    .accessibilityLabel(model.isAttached ? "解除吸附" : "吸附当前 Codex")
                    toolButton("arrow.up.left.and.arrow.down.right", help: "展开额度卡片") { model.compact = false }
                        .opacity(0.75)
                }
            }
            HStack(spacing: 8) {
                miniQuota(model.bucket?.primary, fallback: "5 小时", warningBelow: 30)
                Circle().fill(secondary.opacity(0.45)).frame(width: 2, height: 2).allowsHitTesting(false)
                miniQuota(model.bucket?.secondary, fallback: "每周", warningBelow: 20)
            }
        }.padding(.horizontal, 12).frame(width: 304, height: 46)
        .contextMenu { modeMenu; Button("刷新额度") { model.refresh() }; Button("展开") { model.compact = false } }
        .help(model.error ?? "Codex 剩余额度")
    }

    private func miniQuota(_ window: QuotaWindow?, fallback: String, warningBelow: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(window?.title ?? fallback).font(.system(size: 10)).foregroundStyle(secondary)
            Text(window.map { "\($0.remainingPercent)%" } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(window.map { $0.remainingPercent < warningBelow } == true
                    ? (scheme == .dark ? Color(red: 1, green: 0.68, blue: 0.30) : Color(red: 0.66, green: 0.35, blue: 0.04)) : ink)
        }.lineLimit(1).opacity(model.isStale() ? 0.5 : 1)
        .overlay {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                DragHandle(start: { model.onDragStart?() }, end: { model.onDragEnd?() })
                    .help(resetHelp(window, now: context.date))
            }
        }
    }

    private func resetHelp(_ window: QuotaWindow?, now: Date) -> String {
        guard let window else { return "重置时间未知" }
        var text = window.resetText(now: now)
        if window.windowDurationMins == 10080, let timestamp = window.resetsAt, timestamp > now.timeIntervalSince1970 {
            let date = Date(timeIntervalSince1970: timestamp)
            text = date.formatted(.dateTime.month().day().weekday().hour().minute()) + " 重置（\(text)）"
        }
        if model.isStale(at: now) { text += " · 数据已过期，等待刷新" }
        return text
    }

    private func toolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(secondary).help(help).accessibilityLabel(help)
    }

    @ViewBuilder private var modeMenu: some View {
        ForEach(DisplayMode.allCases, id: \.rawValue) { mode in
            Button { model.mode = mode } label: { Label(mode.title, systemImage: model.mode == mode ? "checkmark" : mode.symbol) }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("组件设置").font(.system(size: 14, weight: .semibold)); Spacer(); Button("完成") { model.settingsOpen = false }.buttonStyle(.plain) }
            Picker("显示模式", selection: $model.mode) {
                ForEach(DisplayMode.allCases, id: \.rawValue) { Text($0.title).tag($0) }
            }
            Text(model.mode == .follow ? "跟随 Codex 移动与显隐；切换到其他应用时收起。" : (model.mode == .always ? "Codex 最小化或隐藏后，组件仍然置顶显示。" : "作为普通窗口显示，不覆盖其他应用。"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("吸附当前 Codex") { model.onAttach?() }
                Button(model.isAttached ? "解除吸附" : "已解除吸附") { model.onDetach?() }
                    .disabled(!model.isAttached)
            }.controlSize(.small)
            Divider()
            Picker("自动刷新", selection: $model.interval) {
                Text("30 秒").tag(30.0); Text("1 分钟").tag(60.0); Text("2 分钟").tag(120.0); Text("5 分钟").tag(300.0)
            }
            Picker("外观", selection: $model.appearance) {
                Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }
            Toggle("登录后自动启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            if let message = model.loginMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                Button("打开系统登录项") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("收起到菜单栏") { model.settingsOpen = false; model.onDismiss?() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 300).onAppear { model.updateLoginStatus() }
    }
}
