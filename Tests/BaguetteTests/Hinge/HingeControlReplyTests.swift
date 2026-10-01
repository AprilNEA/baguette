import Foundation
import Testing
@testable import Baguette

/// What `HingeControl` prints to its owner: its guest pid at startup, then
/// one `done <status>` per command it played. Anything else is diagnostics.
@Suite("HingeControlReply")
struct HingeControlReplyTests {
    @Test(arguments: [
        ("pid 4242", HingeControlReply.pid(4242)),
        ("done 0", .done(0)),
        ("done 3", .done(3)),
    ])
    func `a reply line names its pid or a command's status`(line: String, reply: HingeControlReply) {
        #expect(HingeControlReply(line: line) == reply)
    }

    /// pid 1 is launchd; a stray line must never point the owner's kill at it.
    @Test(arguments: ["bad line: angle x", "dispatch failed: orientation pud", "done", "pid four", "pid 1", "pid 0", "done 0 extra", ""])
    func `diagnostics and malformed lines are not replies`(line: String) {
        #expect(HingeControlReply(line: line) == nil)
    }

    @Test func `replies are read across chunk boundaries and around diagnostics`() {
        var reader = HingeControlReplyReader()
        #expect(reader.append(Data("runtime warning\npi".utf8)) == [])
        #expect(reader.append(Data("d 4242\nbad line: x\ndo".utf8)) == [.pid(4242)])
        #expect(reader.append(Data("ne 0\ndone 1\n".utf8)) == [.done(0), .done(1)])
    }
}
