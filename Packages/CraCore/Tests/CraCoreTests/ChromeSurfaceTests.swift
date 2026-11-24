import CraCore
import Testing

struct ChromeSurfaceTests {
    static func close(_ a: RGB, _ b: RGB) -> Bool { abs(a.r - b.r) < 1e-9 && abs(a.g - b.g) < 1e-9 && abs(a.b - b.b) < 1e-9 }

    /// Arc Default's light half (#CDCDFC → #FFE5E5): a pale tint of both ends, not the raw lavender.
    @Test func lightIsTheGradientsMeanHalfwayToWhite() {
        let stops = [RGB(205 / 255, 205 / 255, 252 / 255), RGB(1, 229 / 255, 229 / 255)]
        let fill = ChromeSurface.fill(stops: stops, dark: false)
        let mean = RGB(230 / 255, 217 / 255, 240.5 / 255)
        #expect(Self.close(fill, mean.mixed(with: RGB(1, 1, 1), ChromeSurface.lightLift)))
        #expect(fill.r + fill.g + fill.b > stops[0].r + stops[0].g + stops[0].b)
    }

    @Test func darkIsTheGradientsMean() {
        let fill = ChromeSurface.fill(stops: [RGB(0.1, 0.1, 0.2), RGB(0.3, 0.1, 0.2)], dark: true)
        #expect(Self.close(fill, RGB(0.2, 0.1, 0.2)))
    }
}
