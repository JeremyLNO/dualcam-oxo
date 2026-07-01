import AVFoundation

/// Writes one camera feed (video + shared audio) to a `.mov` file.
/// All access is serialized on its own queue so it is safe to feed from the
/// capture callback.
final class FeedWriter {
    private let writer: AVAssetWriter?
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let q = DispatchQueue(label: "com.crazybeelabs.dualcam.writer")
    private var started = false
    let url: URL

    init(url: URL, quality: VideoQuality) {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try? AVAssetWriter(outputURL: url, fileType: .mov)

        let dim = quality.dimensions
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dim.height,        // portrait: swap W/H
            AVVideoHeightKey: dim.width,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitrate,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000,
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        if let w = writer {
            if w.canAdd(videoInput) { w.add(videoInput) }
            if w.canAdd(audioInput) { w.add(audioInput) }
        }
    }

    func append(_ sample: CMSampleBuffer, isVideo: Bool) {
        q.async { [weak self] in
            guard let self, let w = self.writer,
                  CMSampleBufferDataIsReady(sample) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if !self.started {
                guard isVideo, w.status == .unknown else { return }   // start on first video frame
                w.startWriting()
                w.startSession(atSourceTime: pts)
                self.started = true
            }
            guard w.status == .writing else { return }
            if isVideo, self.videoInput.isReadyForMoreMediaData {
                self.videoInput.append(sample)
            } else if !isVideo, self.audioInput.isReadyForMoreMediaData {
                self.audioInput.append(sample)
            }
        }
    }

    func finish(_ completion: @escaping () -> Void) {
        q.async { [weak self] in
            guard let self, let w = self.writer, self.started, w.status == .writing else {
                completion(); return
            }
            self.videoInput.markAsFinished()
            self.audioInput.markAsFinished()
            w.finishWriting { completion() }
        }
    }
}
