import Foundation
import Darwin

/// Only local, paired-device diagnostics. Never persist launch keys, credentials,
/// certificate material, or URL query parameters from Moonlight's native logs.
enum DiagnosticRedaction {
    static func sanitize(_ line: String) -> String {
        let lower = line.lowercased()
        let sensitive = ["rikey", "password", "密码", "authorization", "cookie", "access_token",
                         "refresh_token", "private key", "private_key", "clientcert", "client certificate",
                         "servercert", "credentials", "pairing pin", "配对码"]
        if sensitive.contains(where: { lower.contains($0) }) {
            return "[redacted sensitive diagnostic line]"
        }
        if lower.range(of: #"\b(pin|token|secret|pairing[_-]?code)\s*[:=]"#, options: .regularExpression) != nil {
            return "[redacted sensitive diagnostic line]"
        }
        var result = line.replacingOccurrences(of: #"\?[^\s\"<>]*"#, with: "?[redacted query]", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\b[0-9a-fA-F]{32,}\b"#, with: "[redacted token]", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{48,}={0,2}(?![A-Za-z0-9+/])"#,
                                              with: "[redacted long token]", options: .regularExpression)
        return String(result.prefix(4096))
    }
}

/// Single-queue writer; four bounded files (at most about 4 MiB total).
final class DiagnosticLogWriter {
    let directory: URL
    private let maxBytes: Int
    private var handle: FileHandle?
    private var byteCount = 0
    private var redactingPEM = false
    private let timestamp = ISO8601DateFormatter()

    init(directory: URL, maxBytes: Int = 1_048_576) throws {
        self.directory = directory
        self.maxBytes = maxBytes
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try rotate()
    }

    deinit { try? handle?.close() }

    func append(_ raw: String) {
        if raw.contains("-----BEGIN ") { redactingPEM = true }
        let safe = redactingPEM ? "[redacted PEM material]" : DiagnosticRedaction.sanitize(raw)
        if raw.contains("-----END ") { redactingPEM = false }
        let line = "\(timestamp.string(from: Date())) \(safe)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            if byteCount > 0 && byteCount + data.count > maxBytes { try rotate() }
            try handle?.write(contentsOf: data)
            byteCount += data.count
        } catch {
            // Logging must never crash, block, or recursively log a stream error.
        }
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let files = ["current.log", "previous-1.log", "previous-2.log", "previous-3.log"]
            .map { directory.appendingPathComponent($0) }
        let manager = FileManager.default
        if manager.fileExists(atPath: files[3].path) { try manager.removeItem(at: files[3]) }
        for index in stride(from: 2, through: 0, by: -1) {
            if manager.fileExists(atPath: files[index].path) {
                try manager.moveItem(at: files[index], to: files[index + 1])
            }
        }
        guard manager.createFile(atPath: files[0].path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: files[0])
        byteCount = 0
    }
}

/// Capture Swift/C/Objective-C stdout and stderr without a debugger attachment.
/// Disk I/O runs off the UI/render threads. A paired Mac pulls these files using
/// CoreDevice, so no LAN HTTP listener, embedded token, or cloud upload is needed.
final class ClientDiagnostics {
    static let shared = ClientDiagnostics()
    static let enabledKey = "yuDiagnosticsEnabled"
    private let queue = DispatchQueue(label: "yu.moonlight.diagnostics", qos: .utility)
    private var sources: [DispatchSourceRead] = []
    private var pending: [Int32: Data] = [:]
    private var writer: DiagnosticLogWriter?
    private var started = false
    private let cacheDirectory: URL?

    init(cacheDirectory: URL? = nil) { self.cacheDirectory = cacheDirectory }

    private var cachesURL: URL? {
        cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil || UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func preferenceChanged() {
        persistSyncPreference()
        if isEnabled && !started { start() }
    }

    /// Native NSLog can bypass stderr outside Xcode, so mirror our own logger
    /// explicitly as well. Never do disk I/O on the decoder's calling thread.
    func recordNative(_ line: String) {
        guard started, isEnabled else { return }
        let bounded = String(line.prefix(16_384))
        queue.async { [weak self] in self?.writer?.append(bounded) }
    }

    private func persistSyncPreference() {
        guard let caches = cachesURL else { return }
        let directory = caches.appendingPathComponent("YuMoonlightDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONSerialization.data(withJSONObject: ["enabled": isEnabled]) {
            try? data.write(to: directory.appendingPathComponent("sync-preference.json"), options: .atomic)
        }
    }

    func start() {
        persistSyncPreference()
        guard !started, isEnabled,
              let caches = cachesURL else { return }
        do {
            writer = try DiagnosticLogWriter(directory: caches.appendingPathComponent("YuMoonlightDiagnostics", isDirectory: true))
        } catch { return }
        started = true
        // Flush line-oriented printf/Swift print before a crash, rather than only
        // at process exit. stderr is already unbuffered but make it explicit.
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        capture(STDOUT_FILENO)
        capture(STDERR_FILENO)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        queue.async { [self] in
            writer?.append("[Diagnostics] Yu Moonlight build=\(build); \(system); paired-Mac file sync; bounded/redacted logs")
        }
    }

    private func capture(_ descriptor: Int32) {
        let original = dup(descriptor)
        guard original >= 0 else { return }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { close(original); return }
        guard dup2(descriptors[1], descriptor) >= 0 else {
            close(original); close(descriptors[0]); close(descriptors[1]); return
        }
        close(descriptors[1])
        let readFD = descriptors[0]
        _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(original, F_SETFL, fcntl(original, F_GETFL) | O_NONBLOCK)
        _ = fcntl(original, F_SETNOSIGPIPE, 1)
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = read(readFD, &buffer, buffer.count)
                guard count > 0 else { break }
                // Keep Xcode's console useful, but never wait for an absent reader.
                _ = buffer.withUnsafeBytes { write(original, $0.baseAddress, count) }
                guard isEnabled else { pending[descriptor] = Data(); continue }
                var data = pending[descriptor] ?? Data()
                data.append(contentsOf: buffer.prefix(count))
                while let newline = data.firstIndex(of: 10) {
                    let raw = String(decoding: data[..<newline], as: UTF8.self)
                        .trimmingCharacters(in: .newlines)
                    if !raw.isEmpty { writer?.append(raw) }
                    data.removeSubrange(...newline)
                }
                if data.count > 262_144 {
                    writer?.append("[Diagnostics] Discarded oversized unterminated output")
                    data.removeAll(keepingCapacity: false)
                }
                pending[descriptor] = data
            }
        }
        source.setCancelHandler { close(readFD); close(original) }
        sources.append(source)
        source.resume()
    }
}

@_cdecl("MLRecordClientDiagnostic")
func MLRecordClientDiagnostic(_ message: UnsafePointer<CChar>?) {
    guard let message else { return }
    ClientDiagnostics.shared.recordNative(String(cString: message))
}
