import SwiftUI
import AVFoundation

/// A live preview for one multi-cam feed. It attaches an `AVCaptureVideoPreviewLayer`
/// to a specific input port with no implicit connection (required for multi-cam).
struct FeedPreview: UIViewRepresentable {
    let session: AVCaptureMultiCamSession
    let port: AVCaptureInput.Port?
    /// Preview rotation in degrees: 90 = portrait, 0 = landscape.
    var rotationAngle: CGFloat = 90
    /// When set, a tap reports (viewPoint, devicePoint 0…1) for focus/exposure.
    var onFocus: ((CGPoint, CGPoint) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.setSessionWithNoConnection(session)
        v.previewLayer.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        v.addGestureRecognizer(tap)
        v.focusTap = tap
        context.coordinator.view = v
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {
        context.coordinator.onFocus = onFocus
        v.focusTap?.isEnabled = (onFocus != nil)
        guard let port else { return }
        // (Re)establish the connection to this feed's port once it exists.
        if v.attachedPort !== port {
            if let old = v.currentConnection { session.removeConnection(old) }
            let conn = AVCaptureConnection(inputPort: port, videoPreviewLayer: v.previewLayer)
            if session.canAddConnection(conn) {
                session.addConnection(conn)
                v.currentConnection = conn
                v.attachedPort = port
            }
        }
        if let conn = v.currentConnection, conn.isVideoRotationAngleSupported(rotationAngle) {
            conn.videoRotationAngle = rotationAngle
        }
    }

    final class Coordinator {
        weak var view: PreviewView?
        var onFocus: ((CGPoint, CGPoint) -> Void)?
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            let loc = g.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: loc)
            onFocus?(loc, devicePoint)
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var currentConnection: AVCaptureConnection?
        var attachedPort: AVCaptureInput.Port?
        var focusTap: UITapGestureRecognizer?
    }
}

/// Placeholder shown when there's no live feed (Simulator, unsupported, denied).
struct PreviewPlaceholder: View {
    let systemImage: String
    let text: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bg1, Palette.bg0],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.honey)
                Text(text)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.sub)
                    .padding(.horizontal, 24)
            }
        }
    }
}

/// Rule-of-thirds composition grid.
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                for i in 1..<3 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
