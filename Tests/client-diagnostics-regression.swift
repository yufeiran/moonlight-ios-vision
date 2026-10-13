import Foundation
import SwiftUI
import Darwin

@main
struct ClientDiagnosticsRegression {
    static func main() throws {
        if CommandLine.arguments.contains("--capture-smoke") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yu-capture-test-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let capture = ClientDiagnostics(cacheDirectory: directory)
            capture.start()
            print("[Smoke] stdout-ready")
            fputs("[Smoke] stderr-ready\n", stderr)
            print("password=smoke-example-sensitive")
            let log = directory.appendingPathComponent("YuMoonlightDiagnostics/current.log")
            let deadline = Date().addingTimeInterval(2)
            var contents = ""
            repeat {
                usleep(20_000)
                contents = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            } while (!contents.contains("stdout-ready") || !contents.contains("stderr-ready") ||
                     !contents.contains("redacted sensitive")) && Date() < deadline
            precondition(contents.contains("stdout-ready") && contents.contains("stderr-ready"))
            precondition(contents.contains("redacted sensitive") && !contents.contains("smoke-example-sensitive"))
            // Both descriptors are intercepted: use the captured stdout to retain
            // the success signal for the parent regression runner.
            print("PASS: real stdout/stderr capture and sanitized disk writes")
            return
        }
        for secret in ["rikey=abcd1234", "password: example", "Authorization: Bearer example",
                       "clientcert=example", "credentials: example", "-----BEGIN PRIVATE KEY-----", "PIN: 1234"] {
            precondition(DiagnosticRedaction.sanitize(secret) == "[redacted sensitive diagnostic line]")
        }
        let url = DiagnosticRedaction.sanitize("GET https://host/resume?session=example&pin=1234")
        precondition(!url.contains("example") && !url.contains("1234"))
        precondition(DiagnosticRedaction.sanitize("key=0123456789abcdef0123456789abcdef").contains("[redacted token]"))
        precondition(DiagnosticRedaction.sanitize("[LowLatency] Shared Metal active") == "[LowLatency] Shared Metal active")
        print("PASS: credential/query redaction preserves useful diagnostics")

        var optional: String? = "live"
        let retained = retainedSceneBinding(snapshot: optional!)
        optional = nil
        precondition(retained.wrappedValue == "live")
        retained.wrappedValue = "late write"
        precondition(optional == nil && retained.wrappedValue == "live")
        print("PASS: nil scene during child teardown neither traps nor resurrects the scene")

        precondition(ClientWindowSizing.compactStreamSize(width: 3840, height: 2160) == CGSize(width: 1200, height: 675))
        precondition(ClientWindowSizing.compactStreamSize(width: 3840, height: 2160, saved: CGSize(width: 2000, height: 1125)) == CGSize(width: 1200, height: 675))
        precondition(ClientWindowSizing.compactStreamSize(width: 3840, height: 2160, saved: CGSize(width: 640, height: 360)) == CGSize(width: 640, height: 360))
        precondition(ClientWindowSizing.compactStreamSize(width: 0, height: 0).width == 1200)
        precondition(ClientWindowSizing.compactStreamSize(width: 1080, height: 1920).height == 900)
        print("PASS: compact window dimensions, smaller saved sizes, invalid dimensions and portrait streams")

        let suite = "yu-window-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(960.0, forKey: "uikitWindowWidth")
        defaults.set(540.0, forKey: "uikitWindowHeight")
        ClientWindowSizing.migratePreviousStreamDefault(in: defaults)
        precondition(defaults.double(forKey: "uikitWindowWidth") == 1200)
        precondition(defaults.double(forKey: "uikitWindowHeight") == 675)
        ClientWindowSizing.migratePreviousStreamDefault(in: defaults)
        precondition(defaults.double(forKey: "uikitWindowWidth") == 1200)
        defaults.removeObject(forKey: "yuStreamWindowSizeRevision")
        defaults.set(640.0, forKey: "uikitWindowWidth")
        defaults.set(360.0, forKey: "uikitWindowHeight")
        ClientWindowSizing.migratePreviousStreamDefault(in: defaults)
        precondition(defaults.double(forKey: "uikitWindowWidth") == 640)
        print("PASS: previous default enlarges once; custom resizing is preserved")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yu-diagnostic-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let writer = try DiagnosticLogWriter(directory: directory, maxBytes: 256)
            for index in 0..<60 { writer.append("test line \(index) " + String(repeating: "x", count: 80)) }
            writer.append("rikey=example-secret")
            writer.append("-----BEGIN PRIVATE KEY-----")
            writer.append("fake-private-key-body")
            writer.append("-----END PRIVATE KEY-----")
            writer.append("last safe event")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        precondition(files.count == 4)
        for file in files {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
            let content = try String(contentsOf: file, encoding: .utf8)
            precondition(size <= 256)
            precondition(!content.contains("example-secret"))
            precondition(!content.contains("fake-private-key-body"))
        }
        let current = try String(contentsOf: directory.appendingPathComponent("current.log"), encoding: .utf8)
        precondition(current.contains("last safe event"))
        print("PASS: bounded rotation and sanitized persisted logs")
    }
}
