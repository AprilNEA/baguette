import Foundation
import Testing

@Suite("HingeOrientationCommand")
struct HingeOrientationCommandTests {
    @Test func `helper validates orientation and returns dispatch status`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let source = scratch.appending(path: "OrientationTest.m")
        try """
        #import "HingeOrientation.h"
        #include <assert.h>
        int main(void) {
          @autoreleasepool {
            for (NSString *name in @[@"portrait", @"pud", @"landscape-left", @"landscape-right"]) {
              __block int calls = 0;
              int result = dispatchHingeOrientation(name, ^BOOL(const char *value) {
                ++calls;
                assert([name isEqualToString:@(value)]);
                return YES;
              });
              assert(result == 0 && calls == 1);
              assert(dispatchHingeOrientation(name, ^BOOL(const char *value) { return NO; }) == 1);
            }
            for (NSString *name in @[@"", @"garbage", @"landscapeLeft", @"landscapeRight", @"portraitUpsideDown"]) {
              assert(dispatchHingeOrientation(name, ^BOOL(const char *value) {
                assert(0 && "invalid orientation dispatched"); return YES;
              }) == 2);
            }
          }
          return 0;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let binary = scratch.appending(path: "OrientationTest")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["--sdk", "macosx", "clang", "-fobjc-arc", "-framework", "Foundation",
            "-I", root.appending(path: "Injected/HingeControl/Sources").path,
            source.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        try #require(compile.terminationStatus == 0)
        let run = Process()
        run.executableURL = binary
        try run.run()
        run.waitUntilExit()
        #expect(run.terminationStatus == 0)

        // Invalid CLI arguments must fail before creating any HID services.
        let helper = scratch.appending(path: "HingeControl")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        build.arguments = ["--sdk", "macosx", "clang", "-fobjc-arc", "-framework", "Foundation",
            root.appending(path: "Injected/HingeControl/Sources/HingeControl.m").path,
            "-o", helper.path]
        try build.run()
        build.waitUntilExit()
        try #require(build.terminationStatus == 0)
        for arguments in [[], ["orientation"], ["orientation", "bogus"],
                          ["orientation", "landscapeLeft"], ["orientation", "portrait", "extra"]] {
            let invalid = Process()
            invalid.executableURL = helper
            invalid.arguments = arguments
            invalid.standardError = FileHandle.nullDevice
            try invalid.run()
            invalid.waitUntilExit()
            #expect(invalid.terminationStatus == 2)
        }
    }
}
