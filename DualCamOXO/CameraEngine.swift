import AVFoundation
import Combine
import UIKit

/// Drives two simultaneous camera feeds with `AVCaptureMultiCamSession`, records
/// each feed to its own file, and exposes the input ports so SwiftUI can render a
/// live preview for each lens.
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
    private var torchDevice: AVCaptureDevice?

    private var writerA: FeedWriter?
    private var writerB: FeedWriter?
    private var recordStart: Date?
    private var timer: Timer?

    /// Result of a finished recording, consumed by the save pipeline.
    struct Take { let urlA: URL; let urlB: URL; let mode: CaptureMode }
    private(set) var lastTake: Take?

    // MARK: - Lifecycle

    func start(mode: CaptureMode, side: CameraSide, quality: VideoQuality, flash: Bool) {
        #if targetEnvironment(simulator)
        status = .simulator
        return
        #else
        guard AVCaptureMultiCamSession.isMultiCamSupported else { status = .unsupported; return }
        torchOn = flash
        status = .configuring
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { self.status = .denied; return }
            self.sessionQueue.async { self.configure(mode: mode, side: side, quality: quality) }
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

    private func configure(mode: CaptureMode, side: CameraSide, quality: VideoQuality) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

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
            Task { @MainActor in self.status = .unsupported }; return
        }
        torchDevice = [devA, devB].first { $0.hasTorch }

        // Feed B is framed landscape in Portrait+Landscape mode, portrait otherwise.
        let rotB: CGFloat = (mode == .orientation) ? 0 : 90
        guard addFeed(device: devA, output: outputA, rotation: 90, assign: { self.portA = $0 }),
              addFeed(device: devB, output: outputB, rotation: rotB, assign: { self.portB = $0 }) else {
            Task { @MainActor in self.status = .unsupported }; return
        }
        addAudio()
        outputA.setSampleBufferDelegate(self, queue: sessionQueue)
        outputB.setSampleBufferDelegate(self, queue: sessionQueue)
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        session.startRunning()
        Task { @MainActor in self.status = .running; self.applyTorch() }
    }

    private func camera(_ type: AVCaptureDevice.DeviceType, _ pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(type, for: .video, position: pos)
    }

    /// Adds one camera as an input with an explicit (portless) data-output connection,
    /// keeping the raw port so the preview layer can attach to the same source.
    private func addFeed(device: AVCaptureDevice,
                         output: AVCaptureVideoDataOutput,
                         rotation: CGFloat,
                         assign: (AVCaptureInput.Port) -> Void) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInputWithNoConnections(input)
        deviceInputs.append(input)

        guard let port = input.ports(for: .video,
                                     sourceDeviceType: device.deviceType,
                                     sourceDevicePosition: device.position).first else { return false }
        assign(port)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { return false }
        session.addOutputWithNoConnections(output)
        let conn = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(conn) else { return false }
        session.addConnection(conn)
        if conn.isVideoRotationAngleSupported(rotation) { conn.videoRotationAngle = rotation }
        return true
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

    // MARK: - Recording

    func toggleRecording(quality: VideoQuality, mode: CaptureMode) {
        isRecording ? finishRecording() : beginRecording(quality: quality, mode: mode)
    }

    private func beginRecording(quality: VideoQuality, mode: CaptureMode) {
        guard status == .running else { return }
        let dir = FileManager.default.temporaryDirectory
        let stamp = Int(Date().timeIntervalSince1970)
        let urlA = dir.appendingPathComponent("dualcam_\(stamp)_A.mov")
        let urlB = dir.appendingPathComponent("dualcam_\(stamp)_B.mov")
        sessionQueue.async {
            self.writerA = FeedWriter(url: urlA, quality: quality)
            self.writerB = FeedWriter(url: urlB, quality: quality)
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
}

// MARK: - Sample buffer routing

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
