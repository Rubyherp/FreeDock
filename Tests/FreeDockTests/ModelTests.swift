import Testing
import Foundation
@testable import FreeDock

@Test("DockItem encodes and decodes round-trip")
func dockItemRoundTrip() throws {
    let item = DockItem(id: UUID(), appPath: "/Applications/Safari.app", label: "Safari")
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(DockItem.self, from: data)
    #expect(decoded.appPath == "/Applications/Safari.app")
    #expect(decoded.label == "Safari")
}

@Test("DockConfig round-trips all fields")
func dockConfigRoundTrip() throws {
    let item = DockItem(appPath: "/App.app")
    let config = DockConfig(id: UUID(), name: "Test", position: CGPoint(x: 100, y: 200),
                            orientation: .vertical, iconSize: 64, items: [item])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(decoded.name == "Test")
    #expect(decoded.orientation == .vertical)
    #expect(decoded.iconSize == 64)
    #expect(decoded.items.count == 1)
    #expect(decoded.position == CGPoint(x: 100, y: 200))
}

@Test("AppConfig holds multiple docks")
func appConfigMultiple() throws {
    let config = AppConfig(docks: [
        DockConfig(name: "A"),
        DockConfig(name: "B")
    ])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.docks.count == 2)
}

@Test("Empty config is valid")
func emptyConfig() throws {
    let config = AppConfig(docks: [])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.docks.isEmpty)
}

@Test("Orientation raw values")
func orientationRawValues() {
    #expect(Orientation.horizontal.rawValue == "horizontal")
    #expect(Orientation.vertical.rawValue == "vertical")
}
