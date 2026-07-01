import SwiftUI
import AVFoundation

/// The capture screen: the primary feed fills the screen, the secondary feed floats
/// in a draggable picture-in-picture frame. A bottom button switches between
/// Portrait+Landscape and Front+Back.
struct CameraView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = CameraEngine()
    @ObservedObject private var review = ReviewManager.shared

    @State private var showSettings = false
    @State private var toast: String?
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var saving = false

    // PiP position (draggable).
    @State private var pipOffset: CGSize = .zero
    @State private var pipStart: CGSize = .zero

    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()

            // Fullscreen primary feed + grid.
            mainFeed
                .ignoresSafeArea()
            if settings.showGrid, engine.status == .running || engine.status == .simulator {
                GridOverlay().ignoresSafeArea()
            }

            // Floating picture-in-picture secondary feed.
            pipFrame

            // Controls.
            VStack(spacing: 0) {
                topBar
                Spacer()
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let toast {
                VStack {
                    Spacer()
                    Toast(text: toast, systemImage: toastIcon).padding(.bottom, 180)
                }
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
        .onChange(of: settings.mode) { _, _ in resetPip(); restart() }
        .onChange(of: settings.side) { _, _ in restart() }
        .onChange(of: settings.quality) { _, _ in restart() }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings)
        }
        .sheet(isPresented: $review.isPresented) {
            ReviewPromptView(lang: lang)
        }
    }

    // MARK: - Feeds

    /// Primary feed fills the screen. Portrait in both modes.
    private var mainFeed: some View {
        ZStack {
            feedContent(port: engine.portA, rotation: 90, compact: false)
            VStack {
                HStack {
                    feedBadge(mainLabel)
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 108)
            .padding(.leading, 16)
        }
    }

    /// Secondary feed floats in a rounded frame whose shape depends on the mode:
    /// landscape (16:9) in Portrait+Landscape, portrait (9:16) in Front+Back.
    private var pipFrame: some View {
        GeometryReader { geo in
            let landscape = settings.mode == .orientation
            let w: CGFloat = landscape ? geo.size.width * 0.44 : geo.size.width * 0.30
            let h: CGFloat = landscape ? w * 9 / 16 : w * 16 / 9

            ZStack(alignment: .topLeading) {
                feedContent(port: engine.portB,
                            rotation: landscape ? 0 : 90,
                            compact: true)
                feedBadge(pipLabel).padding(6)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .offset(x: pipOffset.width, y: pipOffset.height)
            .position(x: geo.size.width - w / 2 - 16,
                      y: geo.safeAreaInsets.top + h / 2 + 70)
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
    private func feedContent(port: AVCaptureInput.Port?, rotation: CGFloat, compact: Bool) -> some View {
        switch engine.status {
        case .running:
            FeedPreview(session: engine.session, port: port, rotationAngle: rotation)
        case .simulator:
            PreviewPlaceholder(systemImage: compact ? "camera.rotate" : "camera.viewfinder",
                               text: compact ? "" : L.t("simulator_note", lang))
        case .denied:
            if compact {
                PreviewPlaceholder(systemImage: "lock.fill", text: "")
            } else {
                deniedCell
            }
        case .unsupported:
            PreviewPlaceholder(systemImage: "exclamationmark.triangle",
                               text: compact ? "" : L.t("multicam_unsupported", lang))
        default:
            PreviewPlaceholder(systemImage: "camera", text: "")
        }
    }

    private var mainLabel: String {
        settings.mode == .frontBack ? L.t("side_back", lang) : L.t("label_portrait", lang)
    }
    private var pipLabel: String {
        settings.mode == .frontBack ? L.t("side_front", lang) : L.t("label_landscape", lang)
    }

    private func feedBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
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
            Picker("", selection: $settings.quality) {
                ForEach(VideoQuality.allCases) { q in
                    Text(L.t(q.titleKey, lang)).tag(q)
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
        .disabled(engine.isRecording)
    }

    // MARK: - Bottom controls

    private var controls: some View {
        HStack {
            modeSwitch
            Spacer()
            recordButton
            Spacer()
            if settings.mode == .orientation { sideSwitch }
            else { Color.clear.frame(width: 54, height: 54) }
        }
        .padding(.horizontal, 6)
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.snappy) {
                settings.mode = settings.mode == .frontBack ? .orientation : .frontBack
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: settings.mode.icon).font(.system(size: 18, weight: .semibold))
                Text(L.t(settings.mode == .orientation ? "mode_orientation" : "mode_frontback", lang))
                    .font(.system(size: 8, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 62, height: 62)
            .background(Circle().fill(Color.black.opacity(0.4)))
        }
        .disabled(engine.isRecording)
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

    private var recordButton: some View {
        VStack(spacing: 6) {
            Button { toggleRecord() } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    RoundedRectangle(cornerRadius: engine.isRecording ? 6 : 30, style: .continuous)
                        .fill(Palette.record)
                        .frame(width: engine.isRecording ? 30 : 60,
                               height: engine.isRecording ? 30 : 60)
                        .animation(.snappy(duration: 0.2), value: engine.isRecording)
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

    private func startEngine() {
        engine.start(mode: settings.mode, side: settings.side,
                     quality: settings.quality, flash: settings.flashDefault)
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            review.evaluate(force: CommandLine.arguments.contains("-forceReview"))
        }
    }

    private func restart() {
        guard !engine.isRecording else { return }
        engine.stop()
        engine.start(mode: settings.mode, side: settings.side,
                     quality: settings.quality, flash: settings.flashDefault)
    }

    private func resetPip() { withAnimation { pipOffset = .zero; pipStart = .zero } }

    private func flashToggle() { engine.torchOn.toggle() }

    private func toggleRecord() {
        let wasRecording = engine.isRecording
        engine.toggleRecording(quality: settings.quality, mode: settings.mode)
        if wasRecording { saveTake() }
    }

    private func saveTake() {
        guard let take = engine.lastTake else { return }
        saving = true
        Task {
            do {
                try? await Task.sleep(nanoseconds: 400_000_000)
                try await VideoComposer.save(take: take.urlA, and: take.urlB, as: settings.saveMode)
                flash(L.t("saved", lang))
            } catch {
                flash(L.t("save_failed", lang), icon: "exclamationmark.triangle.fill")
            }
            saving = false
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
