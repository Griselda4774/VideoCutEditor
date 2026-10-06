import Foundation

#if canImport(AVFoundation)
import AVFoundation

public final class VideoCutExporter {
    public enum ExportError: Error {
        case missingVideoTrack
        case cannotCreateExportSession
    }

    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?

    public init() {}

    public func cancel() {
        exportSession?.cancelExport()
        progressTask?.cancel()
        progressTask = nil
    }

    public func export(
        sourceURL: URL,
        cuts: [VideoCut],
        outputURL: URL,
        progress: @escaping @Sendable (Float) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(asset.duration)
        let normalizedCuts = VideoCutValidator.normalizedCuts(cuts, duration: duration)
        let keepRanges = VideoCutValidator.keepRanges(duration: duration, removing: normalizedCuts)

        let composition = AVMutableComposition()
        guard
            let sourceVideoTrack = asset.tracks(withMediaType: .video).first,
            let destinationVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            completion(.failure(ExportError.missingVideoTrack))
            return
        }

        let sourceAudioTracks = asset.tracks(withMediaType: .audio)
        let destinationAudioTracks = sourceAudioTracks.map {
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        var cursor = CMTime.zero
        do {
            for range in keepRanges {
                let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
                let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: start, end: end)

                try destinationVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)

                for (index, sourceAudioTrack) in sourceAudioTracks.enumerated() {
                    try destinationAudioTracks[index]?.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
                }

                cursor = cursor + timeRange.duration
            }
        } catch {
            completion(.failure(error))
            return
        }

        destinationVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(ExportError.cannotCreateExportSession))
            return
        }

        self.exportSession = session
        session.outputURL = outputURL
        session.outputFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : session.supportedFileTypes.first
        session.shouldOptimizeForNetworkUse = true

        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled, let session = self.exportSession, session.status == .waiting || session.status == .exporting {
                progress(session.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                self?.progressTask?.cancel()
                progress(1)

                switch session.status {
                case .completed:
                    completion(.success(outputURL))
                case .cancelled:
                    completion(.failure(CancellationError()))
                case .failed:
                    completion(.failure(session.error ?? ExportError.cannotCreateExportSession))
                default:
                    completion(.failure(session.error ?? ExportError.cannotCreateExportSession))
                }
            }
        }
    }
}
#endif
