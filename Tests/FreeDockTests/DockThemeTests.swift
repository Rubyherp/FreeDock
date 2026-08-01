import Foundation
import Testing
@testable import FreeDock

@Suite("Saved appearance themes")
struct DockThemeTests {
    @Test("A theme captures and applies only visual appearance")
    func capturesVisualAppearance() {
        let source = DockConfig(
            name: "Source",
            orientation: .vertical,
            iconSize: 72,
            autoHideWhenDocked: false,
            appearance: .dark,
            surfaceOpacity: 0.55,
            blurStyle: .strong,
            cornerRadius: 27,
            shadowStrength: 1.65
        )
        let theme = DockTheme(name: "Night", dock: source)
        var target = DockConfig(
            name: "Target",
            orientation: .horizontal,
            iconSize: 42,
            items: [.separator()],
            autoHideWhenDocked: true
        )
        let originalID = target.id
        let originalItems = target.items

        theme.apply(to: &target)

        #expect(target.id == originalID)
        #expect(target.items == originalItems)
        #expect(target.orientation == .horizontal)
        #expect(target.iconSize == 42)
        #expect(target.autoHideWhenDocked)
        #expect(target.appearance == .dark)
        #expect(target.surfaceOpacity == 0.55)
        #expect(target.blurStyle == .strong)
        #expect(target.cornerRadius == 27)
        #expect(target.shadowStrength == 1.65)
    }

    @Test("Themes round-trip and clamp malformed visual values")
    func roundTripAndClamp() throws {
        let themeID = UUID()
        let data = Data("""
        {
          "id": "\(themeID.uuidString)",
          "name": "  Clear  ",
          "appearance": "light",
          "surfaceOpacity": 0,
          "blurStyle": "strong",
          "cornerRadius": 100,
          "shadowStrength": 9
        }
        """.utf8)
        let theme = try JSONDecoder().decode(DockTheme.self, from: data)
        let decoded = try JSONDecoder().decode(
            DockTheme.self,
            from: JSONEncoder().encode(theme)
        )

        #expect(decoded.id == themeID)
        #expect(decoded.name == "Clear")
        #expect(decoded.appearance == .light)
        #expect(decoded.surfaceOpacity == DockConfig.surfaceOpacityRange.lowerBound)
        #expect(decoded.cornerRadius == DockConfig.cornerRadiusRange.upperBound)
        #expect(decoded.shadowStrength == DockConfig.shadowStrengthRange.upperBound)
    }
}
