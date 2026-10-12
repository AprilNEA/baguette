import Testing
import Foundation
@testable import Baguette

/// Where an app's preferences live on a simulator. simctl reports the
/// container (`get_app_container`), so nothing here guesses a path —
/// the domain only names *which* container and *which* plist inside it.
@Suite("PreferenceDomain")
struct PreferenceDomainTests {

    @Test func `should look for standard defaults in the app's data container`() throws {
        let domain = try PreferenceDomain(bundleID: "com.example.app")
        #expect(domain.containerArguments(udid: "U")
            == ["simctl", "get_app_container", "U", "com.example.app", "data"])
    }

    @Test func `should look for a suite among the app's App Group containers`() throws {
        // simctl's own `get_app_container … <group id>` exits 117 even for
        // a group the app has (Xcode 27), so the suite is found in the
        // `groups` listing instead.
        let domain = try PreferenceDomain(bundleID: "com.example.app", suite: "group.com.example.shared")
        #expect(domain.containerArguments(udid: "U")
            == ["simctl", "get_app_container", "U", "com.example.app", "groups"])
    }

    @Test func `should look for a suite that is not an App Group in the app's own data container`() throws {
        // `UserDefaults(suiteName: "com.example.debug")` — App Group ids
        // always start with `group.`, so anything else is the app's own.
        let domain = try PreferenceDomain(bundleID: "com.example.app", suite: "com.example.debug")
        #expect(domain.containerArguments(udid: "U")
            == ["simctl", "get_app_container", "U", "com.example.app", "data"])
        #expect(domain.plistPath(inContainerOutput: "/data/Application/A1\n")
            == "/data/Application/A1/Library/Preferences/com.example.debug.plist")
    }

    @Test func `should keep standard defaults in the plist named for the app`() throws {
        let domain = try PreferenceDomain(bundleID: "com.example.app")
        #expect(domain.plistPath(inContainerOutput: "/data/Application/A1\n")
            == "/data/Application/A1/Library/Preferences/com.example.app.plist")
    }

    @Test func `should keep a suite in the plist named for the suite inside its group's container`() throws {
        let domain = try PreferenceDomain(bundleID: "com.example.app", suite: "group.x")
        #expect(domain.plistPath(inContainerOutput: """
        group.x.other\t/Shared/AppGroup/G0
        group.x\t/Shared/AppGroup/G1 with space
        """) == "/Shared/AppGroup/G1 with space/Library/Preferences/group.x.plist")
    }

    @Test func `should find no plist for a suite the app's groups don't include`() throws {
        let domain = try PreferenceDomain(bundleID: "com.example.app", suite: "group.x")
        #expect(domain.plistPath(inContainerOutput: "group.y\t/Shared/AppGroup/G1\n") == nil)
        #expect(domain.plistPath(inContainerOutput: "") == nil)
    }

    @Test func `should find no plist when simctl names no container`() throws {
        #expect(try PreferenceDomain(bundleID: "com.example.app").plistPath(inContainerOutput: "\n") == nil)
    }

    @Test func `should refuse an identifier that could leave the container`() {
        for (bundleID, suite) in [
            ("", nil), ("../etc", nil), ("com/x", nil), ("-help", nil),
            ("com.x", ""), ("com.x", "../../x"), ("com.x", "group/x"),
        ] as [(String, String?)] {
            #expect(throws: PreferenceDomainError.self) {
                try PreferenceDomain(bundleID: bundleID, suite: suite)
            }
        }
    }
}

/// A domain as `defaults export` printed it — the persisted values, each
/// typed, and nothing that would blur an absent key into a stored one.
@Suite("Preferences")
struct PreferencesTests {

    private static func export(_ body: String) -> Data {
        Data(("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        \(body)
        </plist>
        """).utf8)
    }

    @Test func `should read every stored preference with its type from a defaults export`() {
        let preferences = Preferences(export: Self.export(
            "<dict><key>onboardingComplete</key><false/><key>launches</key><integer>3</integer></dict>"
        ))
        #expect(preferences?.values == ["onboardingComplete": .bool(false), "launches": .integer(3)])
    }

    @Test func `should read a domain with nothing stored as no preferences`() {
        #expect(Preferences(export: Self.export("<dict/>"))?.values == [:])
    }

    @Test func `should not read output that is not an exported domain`() {
        #expect(Preferences(export: Data("Invalid device: X".utf8)) == nil)
        #expect(Preferences(export: Self.export("<array/>")) == nil)
    }

    @Test func `should report a stored false as present`() {
        let preferences = Preferences(values: ["seen": .bool(false)])
        #expect(preferences.json(forKey: "seen") as NSDictionary
            == ["key": "seen", "present": true, "type": "bool", "value": false] as NSDictionary)
    }

    @Test func `should report a key that was never stored as absent`() {
        #expect(Preferences(values: [:]).json(forKey: "seen") as NSDictionary
            == ["key": "seen", "present": false] as NSDictionary)
    }

    @Test func `should report the whole domain with every value typed`() {
        let preferences = Preferences(values: ["n": .integer(1)])
        #expect(preferences.json as NSDictionary
            == ["n": ["type": "int", "value": 1]] as NSDictionary)
    }

    @Test func `should report a domain read with the app and suite it came from`() throws {
        let suite = try PreferenceDomain(bundleID: "com.x", suite: "group.x")
        #expect(Preferences(values: ["n": .bool(true)]).json(in: suite) as NSDictionary == [
            "bundleId": "com.x", "suite": "group.x",
            "values": ["n": ["type": "bool", "value": true]],
        ] as NSDictionary)
        #expect(Preferences(values: [:]).json(in: try PreferenceDomain(bundleID: "com.x")) as NSDictionary
            == ["bundleId": "com.x", "values": [:] as [String: Any]] as NSDictionary)
    }
}
