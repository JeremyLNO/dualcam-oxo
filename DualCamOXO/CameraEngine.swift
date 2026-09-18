import AVFoundation
import Combine
import UIKit

/// Drives two simultaneous camera feeds with `AVCaptureMultiCamSession`, records
/// each feed to its own file (or captures stills), and exposes the input ports so
/// SwiftUI can render a live preview for each lens.
///
/// The engine degrades gracefully: on the Simulator (no cameras) or on devices
/// without multi-cam support it stays idle and publishes a status the UI reads to
/// show a placeholder instead of crashing.
@MainActor
final class CameraEngine: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle, configuring, running
        case unsupported          // device can't do multi-cam
        case simulator            // no cameras at all
        case denied               // permission refused
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var torchOn = false { didSet { applyTorch() } }

    let session = AVCaptureMultiCamSession()

    /// Input ports the preview layers connect to. `.a` is the primary feed.
    // Posés sur `sessionQueue` pendant la configuration, lus depuis les vues d'aperçu.
    // `nonisolated(unsafe)` décrit ce passage tel qu'il a toujours eu lieu ; l'annotation
    // ne déplace aucun code, elle cesse juste de prétendre que tout est sur le main actor.
    private(set) nonisolated(unsafe) var portA: AVCaptureInput.Port?
    private(set) nonisolated(unsafe) var portB: AVCaptureInput.Port?

    private let sessionQueue = DispatchQueue(label: "com.crazybeelabs.dualcam.session")
    private nonisolated(unsafe) var deviceInputs: [AVCaptureDeviceInput] = []
    private let outputA = AVCaptureVideoDataOutput()
    private let outputB = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutputA = AVCapturePhotoOutput()
    private let photoOutputB = AVCapturePhotoOutput()
    private nonisolated(unsafe) var torchDevice: AVCaptureDevice?

    // Physical devices behind each feed (for zoom / focus).
    private nonisolated(unsafe) var deviceA: AVCaptureDevice?
    private nonisolated(unsafe) var deviceB: AVCaptureDevice?

    // Written and read on `sessionQueue` (the sample-buffer delegate queue) and read
    // back on the main actor when recording stops. `nonisolated(unsafe)` states that
    // hand-off explicitly instead of letting the compiler assume main-actor isolation
    // it cannot enforce here.
    private nonisolated(unsafe) var writerA: FeedWriter?
    private nonisolated(unsafe) var writerB: FeedWriter?

    /// Read by the capture callback on `sessionQueue`, where it is also written,
    /// so a frame can never reach a writer that has already been torn down.
    /// `isRecording` stays the main-actor copy the UI binds to.
    private nonisolated(unsafe) var recording = false

    /// Frames the pipeline threw away during the last take — thermal throttling,
    /// a saturated encoder, or a disk that cannot keep up. Written on
    /// `sessionQueue`, read once the writers have finished.
    private nonisolated(unsafe) var dropped = 0
    private var recordStart: Date?
    private var timer: Timer?
    private var photoCoordinator: DualPhotoCapture?

    private var currentKind: CaptureKind = .video

    /// Result of a finished recording, consumed by the save pipeline.
    struct Take { let urlA: URL; let urlB: URL; let mode: CaptureMode }
    private(set) var lastTake: Take?

    /// Localization key of something the user should know about the capture
    /// (no room left, frames lost, a writer that failed). The view shows it and
    /// clears it; `nil` means nothing to report.
    @Published var warningKey: String?

    /// Completes once both writers have flushed their `moov` atom. The save
    /// pipeline must await this: reading a file whose `finishWriting` is still
    /// running yields an asset with no tracks (or a truncated one).
    private(set) var writersFinished: Task<Void, Never>?

    // MARK: - Lifecycle

    func start(mode: CaptureMode, side: CameraSide, quality: VideoQuality, flash: Bool, kind: CaptureKind) {
        #if targetEnvironment(simulator)
        status = .simulator
        return
        #else
        guard AVCaptureMultiCamSession.isMultiCamSupported else { status = .unsupported; return }
        torchOn = flash
        currentKind = kind
        status = .configuring
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { self.status = .denied; return }
            self.sessionQueue.async { self.configure(mode: mode, side: side, quality: quality, kind: kind) }
        }
        #endif
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func requestAccess(_ done: @escaping (Bool) -> Void) {
        func mic(_ camOK: Bool) {
            guard camOK else { return done(false) }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: done(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { done($0) }
            default: done(true)   // record video even if mic is off
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: mic(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { mic($0) }
        default: done(false)
        }
    }

    // MARK: - Configuration

    private nonisolated func configure(mode: CaptureMode, side: CameraSide, quality: VideoQuality, kind: CaptureKind) {
        session.beginConfiguration()

        // Reset any prior graph.
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.connections.forEach { session.removeConnection($0) }
        deviceInputs.removeAll()

        let devices: (AVCaptureDevice?, AVCaptureDevice?)
        switch mode {
        case .frontBack:
            devices = (camera(.builtInWideAngleCamera, .back),
                       camera(.builtInWideAngleCamera, .front))
        case .orientation:
            // Two lenses on the same side (wide + ultra-wide, else dual/telephoto).
            let pos = side.avPosition
            devices = (camera(.builtInWideAngleCamera, pos),
                       camera(.builtInUltraWideCamera, pos) ?? camera(.builtInTelephotoCamera, pos))
        }
        guard let devA = devices.0, let devB = devices.1 else {
            session.commitConfiguration()
            Task { @MainActor in self.status = .unsupported }; return
        }
        deviceA = devA; deviceB = devB
        torchDevice = [devA, devB].first { $0.hasTorch }

        // Both feeds are captured UPRIGHT (90° from the natively-landscape sensor).
        // In Portrait+Landscape mode feed B is *framed* 16:9 by cropping at write
        // time (see FeedWriter `landscape:`), never by rotating the image.
        guard let pa = addCameraInput(devA, assign: { self.portA = $0 }),
              let pb = addCameraInput(devB, assign: { self.portB = $0 }) else {
            session.commitConfiguration()
            Task { @MainActor in self.status = .unsupported }; return
        }

        switch kind {
        case .video:
            guard addVideoOutput(port: pa, output: outputA, rotation: 90),
                  addVideoOutput(port: pb, output: outputB, rotation: 90) else {
                session.commitConfiguration()
                Task { @MainActor in self.status = .unsupported }; return
            }
            addAudio()
            outputA.setSampleBufferDelegate(self, queue: sessionQueue)
            outputB.setSampleBufferDelegate(self, queue: sessionQueue)
            audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        case .photo:
            addPhotoOutput(port: pa, output: photoOutputA, rotation: 90)
            addPhotoOutput(port: pb, output: photoOutputB, rotation: 90)
        }

        // Pick the capture format from the requested quality. Without this the two
        // lenses stay on whatever format they booted with and `FeedWriter` merely
        // rescales to the target size — the quality selector would not change a
        // single captured pixel, and "4K" would be an upscale of 1080p.
        applyFormats(devA, devB, quality: quality)

        // `startRunning()` must happen AFTER the configuration block is committed —
        // calling it while still inside begin/commitConfiguration throws NSGenericException.
        session.commitConfiguration()

        session.startRunning()
        Task { @MainActor in self.status = .running; self.currentKind = kind; self.applyTorch() }
    }

    // MARK: - Capture format

    /// Puts both lenses on the best format the requested quality allows, then
    /// steps them down until the pair fits in one hardware budget.
    ///
    /// `hardwareCost` above 1 means the two feeds cannot run together: the session
    /// would fail to start rather than degrade on its own, so the walk down is ours
    /// to do. It is read after the outputs are in place, which is when it is meaningful.
    private nonisolated func applyFormats(_ devA: AVCaptureDevice, _ devB: AVCaptureDevice,
                                          quality: VideoQuality) {
        let formatsA = candidateFormats(devA, quality: quality)
        let formatsB = candidateFormats(devB, quality: quality)
        guard !formatsA.isEmpty, !formatsB.isEmpty else { return }

        var iA = 0, iB = 0
        apply(formatsA[iA], to: devA)
        apply(formatsB[iB], to: devB)

        var steps = 0
        while session.hardwareCost > 1, steps < 16 {
            steps += 1
            // Shrink whichever feed is currently the more expensive one.
            if pixels(formatsA[iA]) >= pixels(formatsB[iB]), iA + 1 < formatsA.count {
                iA += 1; apply(formatsA[iA], to: devA)
            } else if iB + 1 < formatsB.count {
                iB += 1; apply(formatsB[iB], to: devB)
            } else if iA + 1 < formatsA.count {
                iA += 1; apply(formatsA[iA], to: devA)
            } else {
                break   // nothing smaller left on either lens
            }
        }
        #if DEBUG
        let dA = CMVideoFormatDescriptionGetDimensions(formatsA[iA].formatDescription)
        let dB = CMVideoFormatDescriptionGetDimensions(formatsB[iB].formatDescription)
        NSLog("DualCam format: A=%dx%d B=%dx%d coût=%.2f (demandé %@)",
              dA.width, dA.height, dB.width, dB.height, session.hardwareCost, quality.rawValue)
        #endif
    }

    /// Formats one lens can actually use here, best first.
    ///
    /// Multi-cam refuses formats the hardware cannot run two at a time, and the
    /// H.264 writer cannot take the 10-bit `x420` buffers an HDR format delivers,
    /// so both are filtered out rather than discovered at `startRunning()`.
    private nonisolated func candidateFormats(_ device: AVCaptureDevice,
                                              quality: VideoQuality) -> [AVCaptureDevice.Format] {
        let target = quality.dimensions        // landscape, e.g. 1920×1080
        let usable = device.formats.filter { f in
            guard f.isMultiCamSupported else { return false }
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            guard sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    || sub == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return false }
            return f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        // Prefer formats at or under the requested size; fall back to the whole
        // set when the lens has nothing that small (ultra-wide on some models).
        let fits = usable.filter {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width <= Int32(target.width) && d.height <= Int32(target.height)
        }
        return (fits.isEmpty ? usable : fits).sorted { pixels($0) > pixels($1) }
    }

    private nonisolated func pixels(_ format: AVCaptureDevice.Format) -> Int {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(d.width) * Int(d.height)
    }

    private nonisolated func apply(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = format
        // Assigning `activeFormat` resets the frame duration to the format's own
        // default, which can be 60 fps and doubles the hardware cost for nothing.
        // Only the floor is pinned: leaving the ceiling alone keeps the camera's
        // low-light frame-rate drop, which is what buys exposure in the dark.
        if format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        }
        device.unlockForConfiguration()
    }

    private nonisolated func camera(_ type: AVCaptureDevice.DeviceType, _ pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(type, for: .video, position: pos)
    }

    /// Adds one camera as a connectionless input and returns its video port.
    private nonisolated func addCameraInput(_ device: AVCaptureDevice,
                                assign: (AVCaptureInput.Port) -> Void) -> AVCaptureInput.Port? {
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return nil }
        session.addInputWithNoConnections(input)
        deviceInputs.append(input)
        guard let port = input.ports(for: .video,
                                     sourceDeviceType: device.deviceType,
                                     sourceDevicePosition: device.position).first else { return nil }
        assign(port)
        return port
    }

    private nonisolated func addVideoOutput(port: AVCaptureInput.Port, output: AVCaptureVideoDataOutput, rotation: CGFloat) -> Bool {
        guard session.canAddOutput(output) else { return false }
        session.addOutputWithNoConnections(output)
        let conn = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(conn) else { return false }
        session.addConnection(conn)

        // Bi-planar YCbCr is what the sensor delivers and what the H.264 encoder
        // consumes; asking for BGRA inserts a full colour conversion on every
        // frame of both feeds at once. `availableVideoPixelFormatTypes` is only
        // populated once the output is connected, hence the order here.
        let preferred = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                         kCVPixelFormatType_32BGRA]
        if let fmt = preferred.first(where: { output.availableVideoPixelFormatTypes.contains($0) }) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: fmt]
        }
        // Never queue a backlog: a late frame is reported through `didDrop` and
        // counted, rather than delaying every frame behind it.
        output.alwaysDiscardsLateVideoFrames = true
        if conn.isVideoRotationAngleSupported(rotation) { conn.videoRotationAngle = rotation }
        return true
    }

    private nonisolated func addPhotoOutput(port: AVCaptureInput.Port, output: AVCapturePhotoOutput, rotation: CGFloat) {
        guard session.canAddOutput(output) else { return }
        session.addOutputWithNoConnections(output)
        let conn = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(conn) else { return }
        session.addConnection(conn)
        if conn.isVideoRotationAngleSupported(rotation) { conn.videoRotationAngle = rotation }
    }

    private nonisolated func addAudio() {
        guard let mic = AVCaptureDevice.default(for: .audio),
              let micInput = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(micInput) else { return }
        session.addInputWithNoConnections(micInput)
        guard session.canAddOutput(audioOutput),
              let micPort = micInput.ports(for: .audio, sourceDeviceType: mic.deviceType,
                                           sourceDevicePosition: mic.position).first else { return }
        session.addOutputWithNoConnections(audioOutput)
        let conn = AVCaptureConnection(inputPorts: [micPort], output: audioOutput)
        if session.canAddConnection(conn) { session.addConnection(conn) }
    }

    // MARK: - Torch / flash

    private func applyTorch() {
        guard let dev = torchDevice, dev.hasTorch else { return }
        let on = torchOn   // read on the main actor, applied on the session queue
        sessionQueue.async {
            try? dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        }
    }

    // MARK: - Zoom & focus (applied to the feed shown fullscreen)

    /// Pinch zoom. `onA` selects which feed is currently the main (fullscreen) one.
    func setZoom(_ factor: CGFloat, onA: Bool) {
        guard let dev = onA ? deviceA : deviceB else { return }
        sessionQueue.async {
            guard (try? dev.lockForConfiguration()) != nil else { return }
            let maxZ = min(dev.activeFormat.videoMaxZoomFactor, 8)
            dev.videoZoomFactor = max(1, min(factor, maxZ))
            dev.unlockForConfiguration()
        }
    }

    /// Tap to focus / expose at a device point (0…1, from the preview layer).
    func focus(at devicePoint: CGPoint, onA: Bool) {
        guard let dev = onA ? deviceA : deviceB else { return }
        sessionQueue.async {
            guard (try? dev.lockForConfiguration()) != nil else { return }
            if dev.isFocusPointOfInterestSupported {
                dev.focusPointOfInterest = devicePoint
                dev.focusMode = dev.isFocusModeSupported(.autoFocus) ? .autoFocus : .continuousAutoFocus
            }
            if dev.isExposurePointOfInterestSupported {
                dev.exposurePointOfInterest = devicePoint
                dev.exposureMode = dev.isExposureModeSupported(.continuousAutoExposure) ? .continuousAutoExposure : .autoExpose
            }
            dev.unlockForConfiguration()
        }
    }

    // MARK: - Video recording

    func toggleRecording(quality: VideoQuality, mode: CaptureMode) {
        isRecording ? finishRecording() : beginRecording(quality: quality, mode: mode)
    }

    private func beginRecording(quality: VideoQuality, mode: CaptureMode) {
        guard status == .running, currentKind == .video else { return }
        guard hasRoomToRecord(quality) else { warningKey = "warn_low_disk"; return }
        let dir = FileManager.default.temporaryDirectory
        let stamp = Int(Date().timeIntervalSince1970)
        let urlA = dir.appendingPathComponent("dualcam_\(stamp)_A.mov")
        let urlB = dir.appendingPathComponent("dualcam_\(stamp)_B.mov")
        // In Portrait+Landscape mode, feed B is the landscape-framed one (16:9 crop
        // of the same upright image); in Front+Back both stay portrait.
        let bIsLandscape = (mode == .orientation)
        sessionQueue.async {
            self.writerA = FeedWriter(url: urlA, quality: quality)
            self.writerB = FeedWriter(url: urlB, quality: quality, landscape: bIsLandscape)
            self.dropped = 0
            self.recording = true
        }
        recordStart = Date()
        isRecording = true
        elapsed = 0
        lastTake = Take(urlA: urlA, urlB: urlB, mode: mode)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let s = self.recordStart else { return }
            self.elapsed = Date().timeIntervalSince(s)
        }
    }

    private func finishRecording() {
        isRecording = false
        timer?.invalidate(); timer = nil
        let queue = sessionQueue
        writersFinished = Task.detached { [self] in
            let outcome = await withCheckedContinuation { (cont: CheckedContinuation<(Int, Bool), Never>) in
                queue.async {
                    // Closing the gate and releasing the writers on the capture
                    // queue is what makes the hand-off safe: no frame is in flight.
                    self.recording = false
                    let (a, b) = (self.writerA, self.writerB)
                    self.writerA = nil; self.writerB = nil

                    var lost = self.dropped
                    var failed = false
                    let g = DispatchGroup()
                    g.enter(); a?.finish { r in lost += r.droppedAppends; failed = failed || r.failed; g.leave() }
                    g.enter(); b?.finish { r in lost += r.droppedAppends; failed = failed || r.failed; g.leave() }
                    g.notify(queue: .global()) { cont.resume(returning: (lost, failed)) }
                }
            }
            await MainActor.run {
                if outcome.1 { self.warningKey = "warn_write_failed" }
                else if outcome.0 > 5 { self.warningKey = "warn_frames_dropped" }
            }
        }
    }

    /// Refuses to start a take the volume cannot hold: roughly a minute of both
    /// feeds at the selected bitrate. Running out mid-recording leaves two
    /// half-written files and loses the take entirely.
    private func hasRoomToRecord(_ quality: VideoQuality) -> Bool {
        let needed = Int64(quality.bitrate / 8) * 2 * 60
        let free = (try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return free > needed
    }

    // MARK: - Photo capture

    /// Captures a still from each feed and returns both images (primary, secondary).
    func capturePhoto(flash: Bool, completion: @escaping (UIImage?, UIImage?) -> Void) {
        guard status == .running, currentKind == .photo else { completion(nil, nil); return }
        let coordinator = DualPhotoCapture(outputA: photoOutputA, outputB: photoOutputB) { [weak self] a, b in
            self?.photoCoordinator = nil
            Task { @MainActor in completion(a, b) }
        }
        photoCoordinator = coordinator
        sessionQueue.async {
            func makeSettings() -> AVCapturePhotoSettings {
                let s = AVCapturePhotoSettings()
                s.flashMode = flash ? .on : .off
                return s
            }
            self.photoOutputA.capturePhoto(with: makeSettings(), delegate: coordinator)
            self.photoOutputB.capturePhoto(with: makeSettings(), delegate: coordinator)
        }
    }
}

// MARK: - Sample buffer routing (video)

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Called on `sessionQueue` for both video feeds and the microphone.
    ///
    /// Nothing here hops to the main actor. A `Task` per frame retained the
    /// capture buffer well past the pool's budget *and* gave up delivery order —
    /// tasks are not FIFO — so presentation timestamps could reach the writer out
    /// of sequence, where the append is refused without a word.
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard recording else { return }
        if output === outputA { writerA?.append(sampleBuffer, isVideo: true) }
        else if output === outputB { writerB?.append(sampleBuffer, isVideo: true) }
        else {
            writerA?.append(sampleBuffer, isVideo: false)
            writerB?.append(sampleBuffer, isVideo: false)
        }
    }

    /// The pipeline discarding a frame is the only warning a device gives that it
    /// is too hot, too busy or too slow — counted here so the take can say so.
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didDrop sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard recording, output === outputA || output === outputB else { return }
        dropped += 1
    }
}

// MARK: - Dual photo delegate

/// Collects one still from each of the two photo outputs, then fires once with both.
final class DualPhotoCapture: NSObject, AVCapturePhotoCaptureDelegate {
    private let outputA: AVCapturePhotoOutput
    private let outputB: AVCapturePhotoOutput
    private let done: (UIImage?, UIImage?) -> Void
    private var imageA: UIImage?
    private var imageB: UIImage?
    private var received = 0
    private let lock = NSLock()

    init(outputA: AVCapturePhotoOutput, outputB: AVCapturePhotoOutput,
         done: @escaping (UIImage?, UIImage?) -> Void) {
        self.outputA = outputA; self.outputB = outputB; self.done = done
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        lock.lock()
        if output === outputA { imageA = image } else { imageB = image }
        received += 1
        let finished = received >= 2
        lock.unlock()
        if finished { done(imageA, imageB) }
    }
}
