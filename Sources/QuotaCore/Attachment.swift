import Foundation
import CoreGraphics

public enum AttachmentToggleAction: Equatable {
    case attach, detach
    public static func next(isAttached: Bool) -> Self { isAttached ? .detach : .attach }
}

public enum DisplayMode: String, CaseIterable, Codable {
    case follow, always, normal
    public func shouldShow(targetVisible: Bool, targetActive: Bool) -> Bool {
        self != .follow || (targetVisible && targetActive)
    }
    public var title: String {
        switch self { case .follow: return "跟随 Codex"; case .always: return "始终置顶"; case .normal: return "普通窗口" }
    }
    public var symbol: String {
        switch self { case .follow: return "rectangle.on.rectangle"; case .always: return "pin"; case .normal: return "macwindow" }
    }
}

public struct Attachment: Codable, Equatable {
    public enum Edge: String, Codable { case left, right, top, bottom }
    public var edge: Edge
    public var offset: Double
    public init(edge: Edge, offset: Double) { self.edge = edge; self.offset = offset }
    public static func snap(panel: CGRect, target: CGRect, screen: CGRect? = nil, threshold: Double = 28) -> Attachment? {
        var candidates: [(Double, Attachment)] = []
        if panel.maxY > target.minY && panel.minY < target.maxY {
            candidates.append((abs(panel.minX - target.maxX - 8), Attachment(edge: .right, offset: target.maxY - panel.maxY)))
            candidates.append((abs(panel.maxX - target.minX + 8), Attachment(edge: .left, offset: target.maxY - panel.maxY)))
            // Recognize inside placement only when frame() would use that same fallback.
            if let screen, target.maxX + 8 + panel.width > screen.maxX {
                candidates.append((abs(panel.maxX - target.maxX + 8), Attachment(edge: .right, offset: target.maxY - panel.maxY)))
            }
            if let screen, target.minX - 8 - panel.width < screen.minX {
                candidates.append((abs(panel.minX - target.minX - 8), Attachment(edge: .left, offset: target.maxY - panel.maxY)))
            }
        }
        if panel.maxX > target.minX && panel.minX < target.maxX {
            candidates.append((abs(panel.minY - target.maxY - 8), Attachment(edge: .top, offset: panel.minX - target.minX)))
            candidates.append((abs(panel.maxY - target.minY + 8), Attachment(edge: .bottom, offset: panel.minX - target.minX)))
            if let screen, target.maxY + 8 + panel.height > screen.maxY {
                candidates.append((abs(panel.maxY - target.maxY + 8), Attachment(edge: .top, offset: panel.minX - target.minX)))
            }
            if let screen, target.minY - 8 - panel.height < screen.minY {
                candidates.append((abs(panel.minY - target.minY - 8), Attachment(edge: .bottom, offset: panel.minX - target.minX)))
            }
        }
        guard let best = candidates.min(by: { $0.0 < $1.0 }), best.0 <= threshold else { return nil }
        return best.1
    }
    public func frame(target: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .right:
            origin = CGPoint(x: target.maxX + 8, y: target.maxY - size.height - offset)
            if origin.x + size.width > screen.maxX { origin.x = target.maxX - size.width - 8 }
        case .left:
            origin = CGPoint(x: target.minX - size.width - 8, y: target.maxY - size.height - offset)
            if origin.x < screen.minX { origin.x = target.minX + 8 }
        case .top:
            origin = CGPoint(x: target.minX + offset, y: target.maxY + 8)
            if origin.y + size.height > screen.maxY { origin.y = target.maxY - size.height - 8 }
        case .bottom:
            origin = CGPoint(x: target.minX + offset, y: target.minY - size.height - 8)
            if origin.y < screen.minY { origin.y = target.minY + 8 }
        }
        return Self.fit(CGRect(origin: origin, size: size), in: screen)
    }
    public static func fit(_ rect: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: max(screen.minX, min(rect.minX, screen.maxX - rect.width)),
               y: max(screen.minY, min(rect.minY, screen.maxY - rect.height)),
               width: rect.width, height: rect.height)
    }
    public static func resized(_ rect: CGRect, to size: CGSize, screen: CGRect) -> CGRect {
        fit(CGRect(x: rect.minX, y: rect.maxY - size.height, width: size.width, height: size.height), in: screen)
    }
    public func detachedFrame(from panel: CGRect, target: CGRect, screen: CGRect) -> CGRect {
        var result = panel
        var nearby: Attachment? = self
        for _ in 0..<4 {
            guard let edge = nearby?.edge else { break }
            let inside = target.contains(CGPoint(x: result.midX, y: result.midY))
            switch edge {
            case .right: result.origin.x += inside ? -40 : 40
            case .left: result.origin.x += inside ? 40 : -40
            case .top: result.origin.y += inside ? -40 : 40
            case .bottom: result.origin.y += inside ? 40 : -40
            }
            result = Self.fit(result, in: screen)
            nearby = Self.snap(panel: result, target: target, screen: screen)
        }
        return result
    }
}
