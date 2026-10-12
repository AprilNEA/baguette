import ArgumentParser
import Foundation

/// `baguette defaults <read|write|delete> --udid <UDID> --bundle-id <id> [--suite <group>] …`
///
/// Reads and edits an installed app's persisted `UserDefaults` — its
/// standard domain, or an App Group suite — with every value typed. The
/// container lookup and `defaults` spawn live in
/// `Infrastructure/Defaults/SimctlDefaults.swift`; the value types and the
/// quit / relaunch around an edit in `Domain/Defaults/`.
struct DefaultsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "defaults",
        abstract: "Read or edit an app's UserDefaults, typed, including App Group suites",
        subcommands: [Read.self, Write.self, Delete.self]
    )

    /// Which simulator, which app, which suite — shared by all three verbs.
    struct Target: ParsableArguments {
        @OptionGroup var device: DeviceOption

        @Option(name: .customLong("bundle-id"), help: "The app's bundle identifier")
        var bundleID: String

        @Option(help: "An App Group suite (the group identifier) instead of the app's standard defaults")
        var suite: String?

        func domain() throws -> PreferenceDomain {
            try PreferenceDomain(bundleID: bundleID, suite: suite)
        }

        func simulator() throws -> any Simulator {
            guard let simulator = CoreSimulators(deviceSetPath: device.deviceSet)
                .find(udid: device.udid)
            else {
                log("Device \(device.udid) not found")
                throw ExitCode.failure
            }
            return simulator
        }
    }

    /// `baguette defaults read --udid <UDID> --bundle-id <id> [--suite <group>] [--key <k>] [--json]`
    struct Read: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Print the app's persisted defaults, or one key"
        )

        @OptionGroup var target: Target

        @Option(help: "Read only this key (reports whether it is set)")
        var key: String?

        @Flag(help: "Print typed JSON instead of text")
        var json = false

        func run() async throws {
            let preferences: Preferences
            let domain: PreferenceDomain
            do {
                domain = try target.domain()
                preferences = try await target.simulator().defaults().read(domain)
            } catch let exit as ExitCode {
                throw exit
            } catch {
                log("defaults read failed: \(error)")
                throw ExitCode.failure
            }
            guard json else {
                print(Self.text(preferences, key: key))
                return
            }
            let object = key.map(preferences.json(forKey:)) ?? preferences.json(in: domain)
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            )
            print(String(decoding: data, as: UTF8.self))
        }

        /// One `key = value (type)` line per preference, in key order;
        /// collections print as their plist fragment.
        static func text(_ preferences: Preferences, key: String?) -> String {
            let keys = key.map { [$0] } ?? preferences.values.keys.sorted()
            return keys.map { key in
                guard let value = preferences.values[key] else { return "\(key) is not set" }
                return "\(key) = \(display(value)) (\(value.typeName))"
            }.joined(separator: "\n")
        }

        private static func display(_ value: PreferenceValue) -> String {
            switch value {
            case .bool(let flag): return "\(flag)"
            case .integer(let n): return "\(n)"
            case .real(let x): return "\(x)"
            case .string(let s): return s
            case .date, .data:
                return value.json["value"].map { "\($0)" } ?? value.xmlFragment
            case .array, .dictionary: return value.xmlFragment
            }
        }
    }

    /// `baguette defaults write … --key <k> --type <type> --value <v> [--relaunch]`
    struct Write: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "write",
            abstract: "Store a typed value under a key"
        )

        @OptionGroup var target: Target

        @Option(help: "The key to store under")
        var key: String

        @Option(help: ArgumentHelp(
            "The value's type: \(PreferenceType.allValueStrings.joined(separator: " | ")). "
                + "plist takes an XML fragment, for arrays and dictionaries"
        ))
        var type: PreferenceType

        @Option(help: "The value, e.g. false, 3, 1.5, 2026-01-02T03:04:05Z, base64 data, or <array>…</array>")
        var value: String

        @Flag(help: "Quit the app before writing and launch it after, so it starts from the new value")
        var relaunch = false

        func edit() throws -> PreferenceEdit {
            PreferenceEdit(
                domain: try target.domain(),
                key: key,
                change: .set(try PreferenceValue.parse(type: type, value: value)),
                relaunch: relaunch
            )
        }

        func run() async throws {
            do {
                let simulator = try target.simulator()
                _ = try await edit().apply(on: simulator.defaults(), apps: simulator.apps())
            } catch let exit as ExitCode {
                throw exit
            } catch {
                log("defaults write failed: \(error)")
                throw ExitCode.failure
            }
            log("Wrote \(key) for \(target.suite ?? target.bundleID)"
                + (relaunch ? " and relaunched \(target.bundleID)" : ""))
        }
    }

    /// `baguette defaults delete … --key <k> [--relaunch]`
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Remove a key, leaving every other preference alone"
        )

        @OptionGroup var target: Target

        @Option(help: "The key to remove")
        var key: String

        @Flag(help: "Quit the app before removing and launch it after")
        var relaunch = false

        func edit() throws -> PreferenceEdit {
            PreferenceEdit(domain: try target.domain(), key: key, change: .remove, relaunch: relaunch)
        }

        func run() async throws {
            let removed: Bool
            do {
                let simulator = try target.simulator()
                removed = try await edit().apply(on: simulator.defaults(), apps: simulator.apps())
            } catch let exit as ExitCode {
                throw exit
            } catch {
                log("defaults delete failed: \(error)")
                throw ExitCode.failure
            }
            log(removed ? "Removed \(key)" : "\(key) was not set; nothing removed")
        }
    }
}

// Kept in App so Domain stays free of ArgumentParser.
extension PreferenceType: ExpressibleByArgument {
    public init?(argument: String) { self.init(wireName: argument) }
    public static var allValueStrings: [String] { allCases.map(\.wireName) }
}
