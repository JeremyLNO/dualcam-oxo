import SwiftUI
import AVFoundation

/// The capture screen: the primary feed fills the screen, the secondary feed floats
/// in a draggable picture-in-picture frame (tap it to swap). Pinch to zoom, tap to
/// focus. A Photo/Video toggle and an always-visible mode selector sit at the bottom.
struct CameraView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = CameraEngine()
    @ObservedObject private var review = ReviewManager.shared

    @State private var showSettings = false
    @State private var toast: String?
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var saving = false

    // Feed swap + PiP position.
    @State private var swapped = false
    @State private var pipOffset: CGSize = .zero
    @State private var pipStart: CGSize = .zero

    // Zoom + focus.
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var focusPoint: CGPoint?

    private var lang: AppLanguage { AppLanguage.current }
    private var mainIsA: Bool { !swapped }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()

            mainFeed.ignoresSafeArea()
            if settings.showGrid, engine.status == .running || engine.status == .simulator {
                GridOverlay().ignoresSafeArea()
            }

            pipFrame

            VStack(spacing: 0) {
                topBar
                Spacer()
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let toast {
                VStack { Spacer(); Toast(text: toast, systemImage: toastIcon).padding(.bottom, 220) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            startEngine()
            if CommandLine.arguments.contains("-openSettings") { showSettings = true }
        }
        .onDisappear { engine.stop() }
        .onChange(of: settings.mode) { _, _ in resetTransforms(); restart() }
        .onChange(of: settings.side) { _, _ in resetTransforms(); restart() }
        .onChange(of: settings.quality) { _, _ in restart() }
        .onChange(of: settings.captureKind) { _, _ in resetTransforms(); restart() }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(settings) }
        .sheet(isPresented: $review.isPresented) { ReviewPromptView(lang: lang) }
    }

    // MARK: - Feeds

    /// Primary feed fills the screen (portrait). Pinch to zoom, tap to focus.
    private var mainFeed: some View {
        ZStack {
            feedContent(port: mainIsA ? engine.portA : engine.portB,
                        rotation: rotation(isA: mainIsA),
                        compact: false,
                        onFocus: { view, device in handleFocus(view: view, device: device) })
            VStack {
                HStack { feedBadge(label(isA: mainIsA)); Spacer() }
                Spacer()
            }
            .padding(.top, 108).padding(.leading, 16)

            if let p = focusPoint { focusReticle.position(p) }
        }
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { v in
                    let z = max(1, min(zoomBase * v.magnification, 8))
                    zoom = z
                    engine.setZoom(z, onA: mainIsA)
                }
                .onEnded { _ in zoomBase = zoom }
        )
    }

    /// Secondary feed floats in a rounded frame; tap to swap it with the main feed.
    private var pipFrame: some View {
        GeometryReader { geo in
            // Landscape frame only when the PiP currently holds the landscape feed.
            let landscape = settings.mode == .orientation && !swapped
            let w: CGFloat = landscape ? geo.size.width * 0.44 : geo.size.width * 0.30
            let h: CGFloat = landscape ? w * 9 / 16 : w * 16 / 9

            ZStack(alignment: .topLeading) {
                feedContent(port: mainIsA ? engine.portB : engine.portA,
                            rotation: rotation(isA: !mainIsA),
                            compact: true, onFocus: nil)
                feedBadge(label(isA: !mainIsA)).padding(6)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .padding(6)
                    }
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .offset(x: pipOffset.width, y: pipOffset.height)
            .position(x: geo.size.width - w / 2 - 16,
                      y: geo.safeAreaInsets.top + h / 2 + 70)
            .onTapGesture { withAnimation(.snappy) { swapped.toggle(); resetZoom() } }
            .gesture(
                DragGesture()
                    .onChanged { v in
                        pipOffset = CGSize(width: pipStart.width + v.translation.width,
                                           height: pipStart.height + v.translation.height)
                    }
                    .onEnded { _ in pipStart = pipOffset }
            )
            .animation(.snappy(duration: 0.25), value: landscape)
        }
    }

    @ViewBuilder
    private func feedContent(port: AVCaptureInput.Port?, rotation: CGFloat, compact: Bool,
                             onFocus: ((CGPoint, CGPoint) -> Void)?) -> some View {
        switch engine.status {
        case .running:
            FeedPreview(session: engine.session, port: port, rotationAngle: rotation, onFocus: onFocus)
        case .simulator:
            PreviewPlaceholder(systemImage: compact ? "camera.rotate" : "camera.viewfinder",
                               text: compact ? "" : L.t("simulator_note", lang))
        case .denied:
            if compact { PreviewPlaceholder(systemImage: "lock.fill", text: "") } else { deniedCell }
        case .unsupported:
            PreviewPlaceholder(systemImage: "exclamationmark.triangle",
                               text: compact ? "" : L.t("multicam_unsupported", lang))
        default:
            PreviewPlaceholder(systemImage: "camera", text: "")
        }
    }

    /// Both feeds are always rendered upright (90° relative to the sensor, which is
    /// natively landscape). "Landscape framing" comes from the 16:9 container +
    /// aspect-fill crop, NOT from rotating the image — rotating it would show the
    /// world lying on its side.
    private func rotation(isA: Bool) -> CGFloat { 90 }
    private func label(isA: Bool) -> String {
        switch settings.mode {
        case .frontBack:   return isA ? L.t("side_back", lang) : L.t("side_front", lang)
        case .orientation: return isA ? L.t("label_portrait", lang) : L.t("label_landscape", lang)
        }
    }

    private func feedBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private var focusReticle: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Palette.honey, lineWidth: 1.5)
            .frame(width: 74, height: 74)
            .transition(.scale.combined(with: .opacity))
    }

    private var deniedCell: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(Palette.honey)
            Text(L.t("cam_denied_body", lang))
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(Palette.sub).padding(.horizontal, 32)
            Button(L.t("open_settings", lang)) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(.black)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(LinearGradient.honey))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg1)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { flashToggle() } label: {
                Image(systemName: engine.torchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(engine.torchOn ? .black : Palette.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(engine.torchOn ? AnyShapeStyle(LinearGradient.honey)
                                                             : AnyShapeStyle(Color.black.opacity(0.4))))
            }
            Spacer()
            qualityMenu
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
        }
        .padding(.top, 4)
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(VideoQuality.allCases) { q in
                Button {
                    selectQuality(q)
                } label: {
                    Text(L.t(q.titleKey, lang))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dial.high")
                Text(settings.quality.shortLabel).font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).frame(height: 42)
            .background(Capsule().fill(Color.black.opacity(0.4)))
        }
        .disabled(engine.isRecording || settings.captureKind == .photo)
        .opacity(settings.captureKind == .photo ? 0.4 : 1)
    }

    private func selectQuality(_ q: VideoQuality) {
        settings.quality = q
    }

    // MARK: - Bottom controls

    private var controls: some View {
        VStack(spacing: 12) {
            modeSelector
                .disabled(engine.isRecording)
                .opacity(engine.isRecording ? 0.45 : 1)

            kindToggle
                .disabled(engine.isRecording)
                .opacity(engine.isRecording ? 0.45 : 1)

            ZStack {
                shutterButton
                HStack { Spacer(); if settings.mode == .orientation { sideSwitch } }
                    .padding(.horizontal, 6)
            }
        }
    }

    private var modeSelector: some View {
        SegmentedPills(options: [
            (value: CaptureMode.orientation, label: L.t("mode_orientation", lang)),
            (value: CaptureMode.frontBack,   label: L.t("mode_frontback", lang)),
        ], selection: $settings.mode)
    }

    private var kindToggle: some View {
        SegmentedPills(options: [
            (value: CaptureKind.video, label: L.t("video", lang)),
            (value: CaptureKind.photo, label: L.t("photo", lang)),
        ], selection: $settings.captureKind)
    }

    private var sideSwitch: some View {
        Button {
            withAnimation(.snappy) { settings.side = settings.side == .back ? .front : .back }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
        .disabled(engine.isRecording)
    }

    private var shutterButton: some View {
        VStack(spacing: 6) {
            Button { onShutter() } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    if settings.captureKind == .video {
                        RoundedRectangle(cornerRadius: engine.isRecording ? 6 : 30, style: .continuous)
                            .fill(Palette.record)
                            .frame(width: engine.isRecording ? 30 : 60,
                                   height: engine.isRecording ? 30 : 60)
                            .animation(.snappy(duration: 0.2), value: engine.isRecording)
                    } else {
                        Circle().fill(.white).frame(width: 60, height: 60)
                    }
                }
            }
            .disabled(saving || (engine.status != .running && engine.status != .simulator))

            if engine.isRecording {
                Text(timeString(engine.elapsed))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.record)
            } else if saving {
                Text(L.t("saving", lang)).font(.caption).foregroundStyle(Palette.sub)
            }
        }
    }

    // MARK: - Actions

    private var effectiveQuality: VideoQuality { settings.quality }

    private func startEngine() {
        engine.start(mode: settings.mode, side: settings.side, quality: effectiveQuality,
                     flash: settings.flashDefault, kind: settings.captureKind)
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            review.evaluate(force: CommandLine.arguments.contains("-forceReview"))
        }
    }

    private func restart() {
        guard !engine.isRecording else { return }
        engine.stop()
        engine.start(mode: settings.mode, side: settings.side, quality: effectiveQuality,
                     flash: settings.flashDefault, kind: settings.captureKind)
    }

    private func resetTransforms() { resetPip(); resetZoom() }
    private func resetPip() { withAnimation { pipOffset = .zero; pipStart = .zero } }
    private func resetZoom() { zoom = 1; zoomBase = 1 }

    private func flashToggle() { engine.torchOn.toggle() }

    private func handleFocus(view: CGPoint, device: CGPoint) {
        engine.focus(at: device, onA: mainIsA)
        withAnimation(.snappy) { focusPoint = view }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation { focusPoint = nil }
        }
    }

    private func onShutter() {
        settings.captureKind == .video ? toggleRecord() : takePhoto()
    }

    private func toggleRecord() {
        let wasRecording = engine.isRecording
        engine.toggleRecording(quality: effectiveQuality, mode: settings.mode)
        if wasRecording { saveTake() }
    }

    private func saveTake() {
        guard let take = engine.lastTake else { return }
        saving = true
        Task {
            do {
                try? await Task.sleep(nanoseconds: 400_000_000)
                try await VideoComposer.save(take: take.urlA, and: take.urlB, as: settings.saveMode,
                                             layout: settings.combinedLayout, watermarked: false)
                flash(L.t("saved", lang))
            } catch {
                flash(L.t("save_failed", lang), icon: "exclamationmark.triangle.fill")
            }
            saving = false
        }
    }

    private func takePhoto() {
        saving = true
        engine.capturePhoto(flash: engine.torchOn) { a, b in
            Task {
                guard let a, let b else {
                    flash(L.t("save_failed", lang), icon: "exclamationmark.triangle.fill")
                    saving = false; return
                }
                do {
                    try await VideoComposer.savePhotos(a, b, mode: settings.saveMode, layout: settings.combinedLayout,
                                                       watermarked: false)
                    flash(L.t("saved_photo", lang))
                } catch {
                    flash(L.t("save_failed", lang), icon: "exclamationmark.triangle.fill")
                }
                saving = false
            }
        }
    }

    private func flash(_ text: String, icon: String = "checkmark.circle.fill") {
        toastIcon = icon
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
