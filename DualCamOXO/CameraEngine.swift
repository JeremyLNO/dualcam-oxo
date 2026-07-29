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
    private(set) var portA: AVCaptureInput.Port?
    private(set) var portB: AVCaptureInput.Port?

    private let sessionQueue = DispatchQueue(label: "com.crazybeelabs.dualcam.session")
    private var deviceInputs: [AVCaptureDeviceInput] = []
    private let outputA = AVCaptureVideoDataOutput()
    private let outputB = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutputA = AVCapturePhotoOutput()
    private let photoOutputB = AVCapturePhotoOutput()
    private var torchDevice: AVCaptureDevice?

    // Physical devices behind each feed (for zoom / focus).
    private var deviceA: AVCaptureDevice?
    private var deviceB: AVCaptureDevice?

    private var writerA: FeedWriter?
    private var writerB: FeedWriter?
    private var recordStart: Date?
    private var timer: Timer?
    private var photoCoordinator: DualPhotoCapture?

    private var currentKind: CaptureKind = .video

    /// Result of a finished recording, consumed by the save pipeline.
    struct Take { let urlA: URL; let urlB: URL; let mode: CaptureMode }
    private(set) var lastTake: Take?

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

    private func configure(mode: CaptureMode, side: CameraSide, quality: VideoQuality, kind: CaptureKind) {
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

        // `startRunning()` must happen AFTER the configuration block is committed —
        // calling it while still inside begin/commitConfiguration throws NSGenericException.
        session.commitConfiguration()

        session.startRunning()
        Task { @MainActor in self.status = .running; self.currentKind = kind; self.applyTorch() }
    }

    private func camera(_ type: AVCaptureDevice.DeviceType, _ pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(type, for: .video, position: pos)
    }

    /// Adds one camera as a connectionless input and returns its video port.
    private func addCameraInput(_ device: AVCaptureDevice,
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

    private func addVideoOutput(port: AVCaptureInput.Port, output: AVCaptureVideoDataOutput, rotation: CGFloat) -> Bool {
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { return false }
        session.addOutputWithNoConnections(output)
        let conn = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(conn) else { return false }
        session.addConnection(conn)
        if conn.isVideoRotationAngleSupported(rotation) { conn.videoRotationAngle = rotation }
        return true
    }

    private func addPhotoOutput(port: AVCaptureInput.Port, output: AVCapturePhotoOutput, rotation: CGFloat) {
        guard session.canAddOutput(output) else { return }
        session.addOutputWithNoConnections(output)
        let conn = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(conn) else { return }
        session.addConnection(conn)
        if conn.isVideoRotationAngleSupported(rotation) { conn.videoRotationAngle = rotation }
    }

    private func addAudio() {
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
        sessionQueue.async {
            try? dev.lockForConfiguration()
            dev.torchMode = self.torchOn ? .on : .off
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
        let (a, b) = (writerA, writerB)
        writerA = nil; writerB = nil
        sessionQueue.async {
            let g = DispatchGroup()
            g.enter(); a?.finish { g.leave() }
            g.enter(); b?.finish { g.leave() }
            g.wait()
        }
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
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        Task { @MainActor in
            guard self.isRecording else { return }
            if output === self.outputA { self.writerA?.append(sampleBuffer, isVideo: true) }
            else if output === self.outputB { self.writerB?.append(sampleBuffer, isVideo: true) }
            else {
                self.writerA?.append(sampleBuffer, isVideo: false)
                self.writerB?.append(sampleBuffer, isVideo: false)
            }
        }
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
