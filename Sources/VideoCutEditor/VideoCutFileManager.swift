import Foundation

public enum VideoCutFileManager {
    public static var baseDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoCutEditor", isDirectory: true)
    }

    public static func makeOutputURL() throws -> URL {
        try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        return baseDirectoryURL.appendingPathComponent("\(UUID().uuidString).mp4")
    }

    public static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func clearTemporaryFiles() {
        guard FileManager.default.fileExists(atPath: baseDirectoryURL.path) else { return }
        try? FileManager.default.removeItem(at: baseDirectoryURL)
    }
}
