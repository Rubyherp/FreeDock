import Cocoa
import ColorSync
import Foundation

enum DockScreenEdge: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case left
    case right
    case top
    case bottom

    func isCompatible(with orientation: Orientation) -> Bool {
        switch (self, orientation) {
        case (.top, .horizontal), (.bottom, .horizontal),
             (.left, .vertical), (.right, .vertical):
            return true
        default:
            return false
        }
    }
}

struct DockDisplayPlacement: Codable, Equatable, Sendable {
    var displayID: UUID
    var displayName: String?
    var normalizedCenter: CGPoint
    var edge: DockScreenEdge?

    init(
        displayID: UUID,
        displayName: String? = nil,
        normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        edge: DockScreenEdge? = nil
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.normalizedCenter = DockDisplayGeometry.clamped(normalizedCenter)
        self.edge = edge
    }

    private enum CodingKeys: String, CodingKey {
        case displayID
        case displayName
        case normalizedCenter
        case edge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try container.decode(UUID.self, forKey: .displayID)
        displayName = try? container.decode(String.self, forKey: .displayName)
        normalizedCenter = DockDisplayGeometry.clamped(
            (try? container.decode(CGPoint.self, forKey: .normalizedCenter))
                ?? CGPoint(x: 0.5, y: 0.5)
        )
        edge = try? container.decode(DockScreenEdge.self, forKey: .edge)
    }

    func respecting(
        orientation: Orientation,
        autoHideWhenDocked: Bool
    ) -> DockDisplayPlacement {
        guard autoHideWhenDocked,
              edge?.isCompatible(with: orientation) != false
        else {
            var placement = self
            placement.edge = nil
            return placement
        }
        return self
    }
}

struct DockDisplayDescriptor: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let label: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool

    init(
        id: UUID,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isPrimary: Bool,
        label: String? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label ?? name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isPrimary = isPrimary
    }

    func withLabel(_ label: String) -> DockDisplayDescriptor {
        DockDisplayDescriptor(
            id: id,
            name: name,
            frame: frame,
            visibleFrame: visibleFrame,
            isPrimary: isPrimary,
            label: label
        )
    }
}

struct DockDisplayResolution: Equatable, Sendable {
    let display: DockDisplayDescriptor
    let isFallback: Bool
}

enum DockDisplayGeometry {
    static let autoHideRevealThickness: CGFloat = 6

    static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: normalized(point.x),
            y: normalized(point.y)
        )
    }

    static func normalizedCenter(of frame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        return clamped(CGPoint(
            x: (frame.midX - visibleFrame.minX) / visibleFrame.width,
            y: (frame.midY - visibleFrame.minY) / visibleFrame.height
        ))
    }

    static func frame(
        size: CGSize,
        placement: DockDisplayPlacement,
        in visibleFrame: CGRect
    ) -> CGRect {
        let center = CGPoint(
            x: visibleFrame.minX + visibleFrame.width * placement.normalizedCenter.x,
            y: visibleFrame.minY + visibleFrame.height * placement.normalizedCenter.y
        )
        var frame = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        frame = clamped(frame, to: visibleFrame)

        switch placement.edge {
        case .left:
            frame.origin.x = visibleFrame.minX
        case .right:
            frame.origin.x = max(visibleFrame.minX, visibleFrame.maxX - frame.width)
        case .bottom:
            frame.origin.y = visibleFrame.minY
        case .top:
            frame.origin.y = max(visibleFrame.minY, visibleFrame.maxY - frame.height)
        case nil:
            break
        }

        return frame
    }

    static func offset(
        _ placement: DockDisplayPlacement,
        by delta: CGPoint,
        in visibleFrame: CGRect
    ) -> DockDisplayPlacement {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return placement
        }

        var offsetPlacement = placement
        offsetPlacement.normalizedCenter = clamped(CGPoint(
            x: placement.normalizedCenter.x + delta.x / visibleFrame.width,
            y: placement.normalizedCenter.y + delta.y / visibleFrame.height
        ))
        return offsetPlacement
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var frame = frame
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - frame.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - frame.height)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), maximumX)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), maximumY)
        return frame
    }

    static func nearestEdge(
        of frame: CGRect,
        in visibleFrame: CGRect,
        orientation: Orientation
    ) -> DockScreenEdge {
        if orientation == .horizontal {
            return abs(frame.minY - visibleFrame.minY)
                <= abs(frame.maxY - visibleFrame.maxY) ? .bottom : .top
        }
        return abs(frame.minX - visibleFrame.minX)
            <= abs(frame.maxX - visibleFrame.maxX) ? .left : .right
    }

    static func preferredDockingEdge(
        of frame: CGRect,
        on display: DockDisplayDescriptor,
        among displays: [DockDisplayDescriptor],
        orientation: Orientation
    ) -> DockScreenEdge? {
        let exposed = exposedEdges(
            for: frame,
            on: display,
            among: displays
        )
        let compatible = compatibleEdges(for: orientation).filter {
            exposed.contains($0)
        }

        return compatible.min {
            distance(
                from: frame,
                to: $0,
                in: display.visibleFrame
            ) < distance(
                from: frame,
                to: $1,
                in: display.visibleFrame
            )
        }
    }

    static func exposedEdges(
        for dockFrame: CGRect,
        on display: DockDisplayDescriptor,
        among displays: [DockDisplayDescriptor]
    ) -> Set<DockScreenEdge> {
        var exposed = Set(DockScreenEdge.allCases)

        for edge in DockScreenEdge.allCases {
            let restingFrame = dockedFrame(
                dockFrame,
                at: edge,
                in: display.visibleFrame
            )
            let hiddenFrame = autoHiddenFrame(
                restingFrame,
                at: edge,
                in: display.visibleFrame
            )
            if displays.contains(where: {
                $0.id != display.id
                    && intersectionArea(hiddenFrame, $0.frame) > 1
            }) {
                exposed.remove(edge)
            }
        }

        return exposed
    }

    static func dockedFrame(
        _ frame: CGRect,
        at edge: DockScreenEdge,
        in visibleFrame: CGRect
    ) -> CGRect {
        var docked = clamped(frame, to: visibleFrame)
        switch edge {
        case .left:
            docked.origin.x = visibleFrame.minX
        case .right:
            docked.origin.x = max(
                visibleFrame.minX,
                visibleFrame.maxX - docked.width
            )
        case .bottom:
            docked.origin.y = visibleFrame.minY
        case .top:
            docked.origin.y = max(
                visibleFrame.minY,
                visibleFrame.maxY - docked.height
            )
        }
        return docked
    }

    static func bestDisplay(
        for frame: CGRect,
        among displays: [DockDisplayDescriptor]
    ) -> DockDisplayDescriptor? {
        guard !displays.isEmpty else { return nil }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let ranked = displays.map { display in
            DisplayRank(
                display: display,
                intersectionArea: intersectionArea(frame, display.frame),
                containsCenter: display.frame.contains(center),
                squaredDistance: squaredDistance(from: center, to: display.frame)
            )
        }
        return ranked.sorted(by: isBetterRank).first?.display
    }

    static func resolveDisplay(
        for placement: DockDisplayPlacement?,
        panelFrame: CGRect,
        among displays: [DockDisplayDescriptor]
    ) -> DockDisplayResolution? {
        guard !displays.isEmpty else { return nil }

        if let placement {
            if let desired = displays.first(where: {
                $0.id == placement.displayID
            }) {
                return DockDisplayResolution(
                    display: desired,
                    isFallback: false
                )
            }

            guard let fallback = stablePrimary(in: displays) else {
                return nil
            }
            return DockDisplayResolution(
                display: fallback,
                isFallback: true
            )
        }

        guard let automatic = bestDisplay(for: panelFrame, among: displays) else {
            return nil
        }
        return DockDisplayResolution(display: automatic, isFallback: false)
    }

    static func uniquelyLabeled(
        _ displays: [DockDisplayDescriptor]
    ) -> [DockDisplayDescriptor] {
        guard displays.count > 1 else { return displays }

        let primary = stablePrimary(in: displays)
        let groups = Dictionary(grouping: displays) {
            $0.name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        }
        var labels: [UUID: String] = [:]

        for group in groups.values {
            guard group.count > 1 else {
                if let display = group.first {
                    labels[display.id] = display.name
                }
                continue
            }

            let sorted = group.sorted(by: spatiallyPrecedes)
            let candidates = sorted.map { display -> (DockDisplayDescriptor, String) in
                if display.isPrimary {
                    return (display, display.name)
                }
                let suffix = relativePosition(of: display, to: primary)
                return (display, "\(display.name) — \(suffix)")
            }
            let candidateCounts = Dictionary(grouping: candidates, by: \.1)
                .mapValues(\.count)
            var usedCounts: [String: Int] = [:]

            for (display, candidate) in candidates {
                guard candidateCounts[candidate, default: 0] > 1 else {
                    labels[display.id] = candidate
                    continue
                }
                usedCounts[candidate, default: 0] += 1
                labels[display.id] = "\(candidate) \(usedCounts[candidate]!)"
            }
        }

        return displays.sorted(by: spatiallyPrecedes).map {
            $0.withLabel(labels[$0.id] ?? $0.name)
        }
    }

    private struct DisplayRank {
        let display: DockDisplayDescriptor
        let intersectionArea: CGFloat
        let containsCenter: Bool
        let squaredDistance: CGFloat
    }

    private static func isBetterRank(
        _ lhs: DisplayRank,
        _ rhs: DisplayRank
    ) -> Bool {
        if lhs.intersectionArea != rhs.intersectionArea {
            return lhs.intersectionArea > rhs.intersectionArea
        }
        if lhs.intersectionArea > 0,
           lhs.containsCenter != rhs.containsCenter
        {
            return lhs.containsCenter
        }
        if lhs.intersectionArea == 0,
           lhs.squaredDistance != rhs.squaredDistance
        {
            return lhs.squaredDistance < rhs.squaredDistance
        }
        if lhs.display.isPrimary != rhs.display.isPrimary {
            return lhs.display.isPrimary
        }
        return lhs.display.id.uuidString < rhs.display.id.uuidString
    }

    private static func stablePrimary(
        in displays: [DockDisplayDescriptor]
    ) -> DockDisplayDescriptor? {
        displays.filter(\.isPrimary).min {
            $0.id.uuidString < $1.id.uuidString
        } ?? displays.min {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func compatibleEdges(
        for orientation: Orientation
    ) -> [DockScreenEdge] {
        orientation == .horizontal ? [.bottom, .top] : [.left, .right]
    }

    private static func distance(
        from frame: CGRect,
        to edge: DockScreenEdge,
        in visibleFrame: CGRect
    ) -> CGFloat {
        switch edge {
        case .left:
            return abs(frame.minX - visibleFrame.minX)
        case .right:
            return abs(frame.maxX - visibleFrame.maxX)
        case .bottom:
            return abs(frame.minY - visibleFrame.minY)
        case .top:
            return abs(frame.maxY - visibleFrame.maxY)
        }
    }

    private static func autoHiddenFrame(
        _ frame: CGRect,
        at edge: DockScreenEdge,
        in visibleFrame: CGRect
    ) -> CGRect {
        var hidden = frame
        switch edge {
        case .left:
            hidden.origin.x = visibleFrame.minX
                - frame.width
                + autoHideRevealThickness
        case .right:
            hidden.origin.x = visibleFrame.maxX
                - autoHideRevealThickness
        case .bottom:
            hidden.origin.y = visibleFrame.minY
                - frame.height
                + autoHideRevealThickness
        case .top:
            hidden.origin.y = visibleFrame.maxY
                - autoHideRevealThickness
        }
        return hidden
    }

    private static func spatiallyPrecedes(
        _ lhs: DockDisplayDescriptor,
        _ rhs: DockDisplayDescriptor
    ) -> Bool {
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary
        }
        if lhs.frame.midX != rhs.frame.midX {
            return lhs.frame.midX < rhs.frame.midX
        }
        if lhs.frame.midY != rhs.frame.midY {
            return lhs.frame.midY > rhs.frame.midY
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func relativePosition(
        of display: DockDisplayDescriptor,
        to primary: DockDisplayDescriptor?
    ) -> String {
        guard let primary else { return "Display" }
        let deltaX = display.frame.midX - primary.frame.midX
        let deltaY = display.frame.midY - primary.frame.midY

        if abs(deltaX) >= abs(deltaY), deltaX != 0 {
            return deltaX < 0 ? "Left" : "Right"
        }
        if deltaY != 0 {
            return deltaY < 0 ? "Below" : "Above"
        }
        return "Display"
    }

    private static func normalized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let deltaX = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let deltaY = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return deltaX * deltaX + deltaY * deltaY
    }
}

@MainActor
enum DockDisplayManager {
    static var connectedDisplays: [DockDisplayDescriptor] {
        let screens = NSScreen.screens
        let displays: [DockDisplayDescriptor] = screens.enumerated().compactMap {
            index, screen -> DockDisplayDescriptor? in
            guard let id = identifier(for: screen) else { return nil }
            return DockDisplayDescriptor(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isPrimary: index == 0
            )
        }
        return DockDisplayGeometry.uniquelyLabeled(displays)
    }

    static var primaryScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    static func identifier(for screen: NSScreen) -> UUID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let createdUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value),
              let value = CFUUIDCreateString(nil, createdUUID.takeRetainedValue())
        else {
            return nil
        }

        return UUID(uuidString: value as String)
    }

    static func screen(withID id: UUID) -> NSScreen? {
        NSScreen.screens.first { identifier(for: $0) == id }
    }

    static func descriptor(for screen: NSScreen) -> DockDisplayDescriptor? {
        guard let id = identifier(for: screen) else { return nil }
        return connectedDisplays.first { $0.id == id }
    }

    static func screen(containing frame: CGRect) -> NSScreen? {
        guard let descriptor = DockDisplayGeometry.bestDisplay(
            for: frame,
            among: connectedDisplays
        ) else {
            return primaryScreen
        }
        return screen(withID: descriptor.id) ?? primaryScreen
    }
}
