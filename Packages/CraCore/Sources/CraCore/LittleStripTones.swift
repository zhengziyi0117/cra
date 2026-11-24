import Foundation

/// Little Windows follow macOS. Only the target space's name takes its accent.
public struct LittleStripTones: Equatable, Sendable {
    public static let stripLeft = RGB(0x24 / 255, 0x24 / 255, 0x38 / 255)
    public static let stripRight = RGB(0x31 / 255, 0x23 / 255, 0x39 / 255)
    public static let lightLeft = RGB(0xf2 / 255, 0xf2 / 255, 0xf6 / 255)
    public static let lightRight = RGB(0xec / 255, 0xea / 255, 0xf0 / 255)

    public var left: RGB
    public var right: RGB
    public var spaceName: RGB

    public init(target theme: SpaceTheme, systemDark: Bool) {
        let shown = theme.resolved(systemDark: systemDark)
        let c = HexColor.components(shown.accent ?? shown.colors.first ?? "#FFFFFF") ?? (0.5, 0.5, 0.5)
        left = systemDark ? Self.stripLeft : Self.lightLeft
        right = systemDark ? Self.stripRight : Self.lightRight
        let accent = RGB(c.r, c.g, c.b)
        spaceName = systemDark ? accent.mixed(with: .white, 0.72) : accent.mixed(with: .black, 0.56)
    }
}
