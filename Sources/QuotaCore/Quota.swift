import Foundation

public struct QuotaWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var remainingPercent: Int { Int((100 - min(100, max(0, usedPercent))).rounded(.down)) }
    public var title: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "额度窗口" }
        if minutes == 10080 { return "每周" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
    public func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "重置时间未知" }
        let seconds = resetsAt - now.timeIntervalSince1970
        guard seconds > 0 else { return "等待额度更新" }
        let minutes = Int(min(5256000, ceil(seconds / 60)))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时后重置" }
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟后重置" }
        return "\(minutes) 分钟后重置"
    }
}

public struct QuotaBucket: Decodable, Equatable, Identifiable {
    public var limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let planType: String?
    public var id: String { limitId ?? "codex" }
}

public struct QuotaSnapshot {
    public let buckets: [QuotaBucket]
    public let availableResetCredits: Int?
    public enum ReadError: Error { case unavailable }
    public static func decode(_ data: Data) throws -> QuotaSnapshot {
        struct ResetCredits: Decodable { let availableCount: Int }
        struct Envelope: Decodable {
            let rateLimits: QuotaBucket?
            let rateLimitsByLimitId: [String: QuotaBucket]?
            let rateLimitResetCredits: ResetCredits?
        }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        var buckets: [QuotaBucket] = []
        if let map = value.rateLimitsByLimitId, !map.isEmpty {
            buckets = map.map { key, original in
                var bucket = original
                bucket.limitId = key
                return bucket
            }.sorted { a, b in
                if a.id == "codex" { return b.id != "codex" }
                if b.id == "codex" { return false }
                return a.id < b.id
            }
        } else if let legacy = value.rateLimits { buckets = [legacy] }
        guard buckets.contains(where: { $0.primary != nil || $0.secondary != nil }) else { throw ReadError.unavailable }
        return QuotaSnapshot(buckets: buckets, availableResetCredits: value.rateLimitResetCredits?.availableCount)
    }
}
