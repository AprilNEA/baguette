import Foundation
import Testing

/// The guest helper's side of the host protocol, compiled for macOS from
/// `Injected/HingeControl/Sources`: a `--deadline` after which a helper that
/// has not started refuses to act, and one `done <status>` reply per command.
@Suite("HingeControlProtocol")
struct HingeControlProtocolTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Injected/HingeControl/Sources")

    @Test func `serve answers every command with its status and skips blank lines`() throws {
        try Self.runProgram("""
        #import "HingeProtocol.h"
        #include <assert.h>
        #include <string.h>
        int main(void) {
          @autoreleasepool {
            char script[] = "angle 10\\n\\n   \\nbogus\\norientation pud\\n";
            FILE *input = fmemopen(script, strlen(script), "r");
            char *text = NULL; size_t length = 0;
            FILE *output = open_memstream(&text, &length);
            NSMutableArray<NSString *> *seen = [NSMutableArray array];
            serveHingeCommands(input, output, ^int(NSArray<NSString *> *words) {
              [seen addObject:[words componentsJoinedByString:@" "]];
              if ([words.firstObject isEqualToString:@"bogus"]) return 2;
              if ([words.firstObject isEqualToString:@"orientation"]) return 1;
              return 0;
            });
            fclose(output);
            assert([seen isEqualToArray:(@[@"angle 10", @"bogus", @"orientation pud"])]);
            assert(strcmp(text, "done 0\\ndone 2\\ndone 1\\n") == 0);
          }
          return 0;
        }
        """)
    }

    @Test func `deadlines are finite Unix times and a passed one is detected`() throws {
        try Self.runProgram("""
        #import "HingeProtocol.h"
        #include <assert.h>
        int main(void) {
          @autoreleasepool {
            double deadline = 0;
            assert(parseHingeDeadline("1790615000.25", &deadline) && deadline == 1790615000.25);
            const char *invalid[] = {"", "soon", "12x", "inf", "nan"};
            for (int i = 0; i < 5; i++) assert(!parseHingeDeadline(invalid[i], &deadline));
            assert(hingeDeadlinePassed(1));
            assert(!hingeDeadlinePassed([NSDate date].timeIntervalSince1970 + 3600));
          }
          return 0;
        }
        """)
    }

    /// Every case here must exit before the helper creates HID services.
    @Test func `a helper started after its deadline does nothing and malformed deadlines are rejected`() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let helper = scratch.appending(path: "HingeControl")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        build.arguments = ["--sdk", "macosx", "clang", "-fobjc-arc", "-framework", "Foundation",
            Self.sources.appending(path: "HingeControl.m").path, "-o", helper.path]
        try build.run()
        build.waitUntilExit()
        try #require(build.terminationStatus == 0)
        let cases: [([String], Int32)] = [
            (["--deadline", "1", "orientation", "portrait"], 3),
            (["--deadline", "1", "serve"], 3),
            (["--deadline"], 2),
            (["--deadline", "soon", "orientation", "portrait"], 2),
            (["--deadline", "1"], 2),
            (["--deadline", "1", "orientation", "bogus"], 2),
        ]
        for (arguments, expected) in cases {
            let process = Process()
            let output = Pipe()
            process.executableURL = helper
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == expected, "\(arguments)")
            // A helper that does nothing never announces a pid to stop.
            #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty, "\(arguments)")
        }
    }

    /// Compile `source` against the helper headers for macOS and require it to exit 0.
    private static func runProgram(_ source: String) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appending(path: "ProtocolTest.m")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let binary = scratch.appending(path: "ProtocolTest")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["--sdk", "macosx", "clang", "-fobjc-arc", "-framework", "Foundation",
            "-I", sources.path, file.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        try #require(compile.terminationStatus == 0)
        let run = Process()
        run.executableURL = binary
        try run.run()
        run.waitUntilExit()
        #expect(run.terminationStatus == 0)
    }
}
