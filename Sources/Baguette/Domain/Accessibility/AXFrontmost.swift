import Foundation

enum AXFrontmost {
    enum Failure: Error, Equatable, LocalizedError {
        case invalidPID(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidPID(let pid): "The guest frontmost query returned an invalid process identifier: \(pid)."
            }
        }
    }

    static func pid(from data: Data) throws -> Int32 {
        struct Response: Decodable { let pid: Int32 }
        let pid = try JSONDecoder().decode(Response.self, from: data).pid
        guard pid > 0 else { throw Failure.invalidPID(pid) }
        return pid
    }
}
