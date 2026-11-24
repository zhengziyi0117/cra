import Foundation

/// The fill of a card, menu, tip or toast button drawn over a page in a space's colours (Cra's look:
/// Arc's menus are always dark, ArcMenuTones). Dark: the gradient's mean. Light: the mean lifted
/// halfway to white, a hint of the space as its sidebar shows over the light material. The raw first
/// stop over a menu-sized area read heavy next to the gradient it came from (#CDCDFC on Arc Default,
/// beside its pink end).
public enum ChromeSurface {
    public static let lightLift = 0.55

    public static func fill(stops: [RGB], dark: Bool) -> RGB {
        guard !stops.isEmpty else { return dark ? RGB(0.12, 0.12, 0.12) : RGB(1, 1, 1) }
        let n = Double(stops.count)
        let mean = RGB(stops.reduce(0) { $0 + $1.r } / n, stops.reduce(0) { $0 + $1.g } / n, stops.reduce(0) { $0 + $1.b } / n)
        return dark ? mean : mean.mixed(with: RGB(1, 1, 1), lightLift)
    }
}
