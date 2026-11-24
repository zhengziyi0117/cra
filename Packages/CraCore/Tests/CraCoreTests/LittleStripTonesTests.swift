import CraCore
import Testing

struct LittleStripTonesTests {
    static func bytes(_ c: RGB) -> [Int] { [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } }

    /// The reporter's Work space (a green-teal gradient), a yellow space, Arc's default blue, a dark
    /// theme, and an Auto theme with two different halves.
    static let themes: [SpaceTheme] = [
        SpaceTheme(colors: ["#6E9A72", "#2E7A78"], intensity: 0.7, noise: 0.1, appearance: "light"),
        SpaceTheme(colors: ["#F8D558"], intensity: 0.6, noise: 0.1, appearance: "light"),
        SpaceTheme(colors: ["#3139FB"], intensity: 0.6, noise: 0.1, appearance: "dark"),
        SpaceTheme(colors: ["#141318", "#2B2638"], intensity: 0.9, noise: 0.14, appearance: "dark", accent: "#E63333"),
        SpaceTheme(light: SpaceTheme(colors: ["#F8D558"], intensity: 0.6, noise: 0.1, appearance: "light"),
                   dark: SpaceTheme(colors: ["#2861B3"], intensity: 0.6, noise: 0.1, appearance: "dark")),
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"), .bug("https://github.com/VictorKildahl/cra/issues/329"),
          arguments: themes, [false, true])
    func theStripFollowsMacOSAcrossSpaces(theme: SpaceTheme, systemDark: Bool) {
        let tones = LittleStripTones(target: theme, systemDark: systemDark)
        #expect(Self.bytes(tones.left) == (systemDark ? [0x24, 0x24, 0x38] : [0xf2, 0xf2, 0xf6]))
        #expect(Self.bytes(tones.right) == (systemDark ? [0x31, 0x23, 0x39] : [0xec, 0xea, 0xf0]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"))
    func onlyTheSpaceNameTakesTheSpacesColour() {
        let work = LittleStripTones(target: Self.themes[0], systemDark: true)
        let yellow = LittleStripTones(target: Self.themes[1], systemDark: true)
        #expect(work.left == yellow.left && work.right == yellow.right)
        #expect(work.spaceName != yellow.spaceName)
        // The colour (its accent first) 72 % of the way to white: #F8D558 → (253, 243, 208).
        #expect(Self.bytes(yellow.spaceName) == [253, 243, 208])
        let w = Self.bytes(work.spaceName)
        #expect(w[1] > w[0], "a green space's name stays green: \(w)")
        let accent = LittleStripTones(target: Self.themes[3], systemDark: true)
        #expect(Self.bytes(accent.spaceName) == [248, 198, 198])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"))
    func anAutoThemesNameAndStripFollowMacOS() {
        let light = LittleStripTones(target: Self.themes[4], systemDark: false)
        let dark = LittleStripTones(target: Self.themes[4], systemDark: true)
        #expect(light.left != dark.left && light.right != dark.right)
        #expect(Self.bytes(light.spaceName) == [109, 94, 39])
        #expect(light.spaceName != dark.spaceName)
    }
}
