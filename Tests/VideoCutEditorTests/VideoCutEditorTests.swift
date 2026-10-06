import Foundation
import Testing
@testable import VideoCutEditor

@Test func normalizedCutsClampSortAndMerge() async throws {
    let input = [
        VideoCut(startTime: 20, endTime: 25),
        VideoCut(startTime: -2, endTime: 2),
        VideoCut(startTime: 1, endTime: 5),
        VideoCut(startTime: 24, endTime: 40),
        VideoCut(startTime: 8, endTime: 8)
    ]

    let result = VideoCutValidator.normalizedCuts(input, duration: 30)

    #expect(result.count == 2)
    #expect(result[0] == VideoCut(startTime: 0, endTime: 5))
    #expect(result[1] == VideoCut(startTime: 20, endTime: 30))
}

@Test func keepRangesFromCuts() async throws {
    let cuts = [
        VideoCut(startTime: 5, endTime: 10),
        VideoCut(startTime: 15, endTime: 18)
    ]

    let ranges = VideoCutValidator.keepRanges(duration: 20, removing: cuts)

    #expect(ranges.count == 3)
    #expect(ranges[0].lowerBound == 0)
    #expect(ranges[0].upperBound == 5)
    #expect(ranges[1].lowerBound == 10)
    #expect(ranges[1].upperBound == 15)
    #expect(ranges[2].lowerBound == 18)
    #expect(ranges[2].upperBound == 20)
}

@Test func temporaryFilePathAndCleanup() async throws {
    let outputURL = try VideoCutFileManager.makeOutputURL()
    #expect(outputURL.path.contains("/VideoCutEditor/"))
    #expect(outputURL.pathExtension == "mp4")

    let data = Data("test".utf8)
    try data.write(to: outputURL)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))

    VideoCutFileManager.remove(outputURL)
    #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)

    let anotherURL = try VideoCutFileManager.makeOutputURL()
    try data.write(to: anotherURL)
    VideoCutFileManager.clearTemporaryFiles()
    #expect(FileManager.default.fileExists(atPath: anotherURL.path) == false)
}
