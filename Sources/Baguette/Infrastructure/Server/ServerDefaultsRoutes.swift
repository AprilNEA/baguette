import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdWebSocket
import NIOCore

/// The `UserDefaults` routes — the same three operations as `baguette
/// defaults`, for a browser editor. Kept out of `Server.swift`'s main body
/// alongside `ServerInterfaceRoutes` / `ServerDeepLinkRoutes`.
extension Server {

    /// `GET    /simulators/:udid/defaults.json?bundleId=…[&suite=…][&key=…]`
    /// `POST   /simulators/:udid/defaults`   `{"bundleId","suite"?,"key","type","value","relaunch"?}`
    ///                                       or `{"bundleId","suite"?,"values":{…},"relaunch"?}` to import
    /// `DELETE /simulators/:udid/defaults?bundleId=…[&suite=…]&key=…[&relaunch=1]`
    ///
    /// All three ride the browser-trust check and none is plugin-reachable:
    /// rewriting an app's preferences is not a capability any plugin
    /// declares today.
    func registerDefaultsRoutes(
        on router: Router<BasicWebSocketRequestContext>,
        rejectUntrustedBrowser: @escaping @Sendable (Request) -> Response?
    ) {
        let simulators = self.simulators

        router.get("/simulators/:udid/defaults.json") { r, _ in
            if let rejected = rejectUntrustedBrowser(r) { return rejected }
            return Self.defaultsResponse(await Self.readDefaults(
                udid: Self.udidParam(r), query: Self.defaultsQuery(r), simulators: simulators
            ), udid: Self.udidParam(r))
        }

        router.post("/simulators/:udid/defaults") { r, _ in
            if let rejected = rejectUntrustedBrowser(r) { return rejected }
            let buffer = try? await r.body.collect(upTo: 1024 * 1024)
            let body = buffer.map { String(buffer: $0) } ?? ""
            return Self.defaultsResponse(await Self.writeDefaults(
                udid: Self.udidParam(r), body: body, simulators: simulators
            ), udid: Self.udidParam(r))
        }

        router.delete("/simulators/:udid/defaults") { r, _ in
            if let rejected = rejectUntrustedBrowser(r) { return rejected }
            return Self.defaultsResponse(await Self.deleteDefaults(
                udid: Self.udidParam(r), query: Self.defaultsQuery(r), simulators: simulators
            ), udid: Self.udidParam(r))
        }
    }

    private static func defaultsQuery(_ r: Request) -> [String: String] {
        var query: [String: String] = [:]
        for name in ["bundleId", "suite", "key", "relaunch"] {
            if let value = r.uri.queryParameters.get(name) { query[name] = String(value) }
        }
        return query
    }

    private static func defaultsResponse(_ outcome: DefaultsOutcome, udid: String) -> Response {
        switch outcome {
        case .ok(let json): return jsonResponse(json)
        case .badRequest(let message): return pluginError(message, status: .badRequest)
        case .unknownDevice: return pluginError("unknown udid: \(udid)", status: .notFound)
        case .notFound(let message): return pluginError(message, status: .notFound)
        case .conflict(let message): return pluginError(message, status: .conflict)
        case .failed(let message): return pluginError(message, status: .internalServerError)
        }
    }

    // MARK: - dispatch

    /// One case per HTTP status. Each failure carries the message the
    /// caller can act on — which app, which group, boot the device.
    enum DefaultsOutcome: Equatable {
        case ok(String)
        case badRequest(String)
        case unknownDevice
        /// The app isn't installed, or has no such App Group.
        case notFound(String)
        /// The simulator is shut down.
        case conflict(String)
        case failed(String)
    }

    /// The whole suite, or one key as present / absent.
    static func readDefaults(
        udid: String, query: [String: String], simulators: any Simulators
    ) async -> DefaultsOutcome {
        let suite: PreferenceSuite
        do {
            suite = try PreferenceSuite(bundleID: query["bundleId"] ?? "", name: query["suite"])
        } catch {
            return .badRequest("\(error)")
        }
        guard !udid.isEmpty, let sim = simulators.find(udid: udid) else { return .unknownDevice }
        do {
            let preferences = try await sim.defaults().read(suite)
            let json = query["key"].map(preferences.json(forKey:)) ?? preferences.json(in: suite)
            return .ok(jsonString(json))
        } catch {
            return outcome(for: error)
        }
    }

    /// Store one typed value. `value` may be a JSON string, number or
    /// boolean; it is read as `type` either way, so `"value": 3` with
    /// `"type": "float"` stores a real.
    static func writeDefaults(
        udid: String, body: String, simulators: any Simulators
    ) async -> DefaultsOutcome {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)),
              let fields = object as? [String: Any]
        else { return .badRequest("defaults body must be a JSON object") }
        if let values = fields["values"] {
            return await importDefaults(fields: fields, values: values, udid: udid, simulators: simulators)
        }
        guard let key = fields["key"] as? String, !key.isEmpty else {
            return .badRequest("key is required")
        }
        guard let type = (fields["type"] as? String).flatMap(PreferenceType.init(wireName:)) else {
            let names = PreferenceType.allCases.map(\.wireName).joined(separator: " | ")
            return .badRequest("type must be one of \(names)")
        }
        guard let text = valueText(fields["value"]) else {
            return .badRequest("value is required (a string, number or boolean)")
        }
        let edit: PreferenceEdit
        do {
            edit = PreferenceEdit(
                suite: try PreferenceSuite(
                    bundleID: fields["bundleId"] as? String ?? "", name: fields["suite"] as? String
                ),
                key: key,
                change: .set(try PreferenceValue.parse(type: type, value: text)),
                relaunch: fields["relaunch"] as? Bool ?? false
            )
        } catch {
            return .badRequest("\(error)")
        }
        return await apply(edit, udid: udid, simulators: simulators) { _ in #"{"ok":true}"# }
    }

    /// A body carrying `values` (a `defaults export`'s map) writes them all,
    /// relaunching once around the batch when asked.
    private static func importDefaults(
        fields: [String: Any], values: Any, udid: String, simulators: any Simulators
    ) async -> DefaultsOutcome {
        let restore: PreferenceImport
        do {
            let map = try JSONSerialization.data(withJSONObject: ["values": values])
            restore = PreferenceImport(
                suite: try PreferenceSuite(
                    bundleID: fields["bundleId"] as? String ?? "", name: fields["suite"] as? String
                ),
                preferences: try Preferences(importing: map),
                relaunch: fields["relaunch"] as? Bool ?? false
            )
        } catch {
            return .badRequest("\(error)")
        }
        guard !udid.isEmpty, let sim = simulators.find(udid: udid) else { return .unknownDevice }
        do {
            let written = try await restore.apply(on: sim.defaults(), apps: sim.apps())
            return .ok(#"{"ok":true,"written":\#(written)}"#)
        } catch {
            return outcome(for: error)
        }
    }

    /// Remove one key; `removed` says whether it was stored.
    static func deleteDefaults(
        udid: String, query: [String: String], simulators: any Simulators
    ) async -> DefaultsOutcome {
        guard let key = query["key"], !key.isEmpty else { return .badRequest("key is required") }
        let edit: PreferenceEdit
        do {
            edit = PreferenceEdit(
                suite: try PreferenceSuite(bundleID: query["bundleId"] ?? "", name: query["suite"]),
                key: key,
                change: .remove,
                relaunch: ["1", "true"].contains(query["relaunch"] ?? "")
            )
        } catch {
            return .badRequest("\(error)")
        }
        return await apply(edit, udid: udid, simulators: simulators) {
            #"{"ok":true,"removed":\#($0)}"#
        }
    }

    private static func apply(
        _ edit: PreferenceEdit, udid: String, simulators: any Simulators,
        answer: (Bool) -> String
    ) async -> DefaultsOutcome {
        guard !udid.isEmpty, let sim = simulators.find(udid: udid) else { return .unknownDevice }
        do {
            return .ok(answer(try await edit.apply(on: sim.defaults(), apps: sim.apps())))
        } catch {
            return outcome(for: error)
        }
    }

    private static func outcome(for error: Error) -> DefaultsOutcome {
        switch error as? DefaultsError {
        case .appNotInstalled?, .groupNotFound?: return .notFound("\(error)")
        case .deviceNotBooted?: return .conflict("\(error)")
        default: return .failed("\(error)")
        }
    }

    /// A JSON scalar as the text `PreferenceValue.parse` reads. Booleans
    /// are checked first: `NSNumber` carries them too.
    private static func valueText(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "true" : "false"
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
