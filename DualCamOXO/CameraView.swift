import SwiftUI
import AVFoundation

/// The capture screen: two stacked feeds, mode/quality/flash controls, record button.
struct CameraView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = CameraEngine()
    @ObservedObject private var review = ReviewManager.shared

    @State private var showSettings = false
    @State private var toast: String?
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var saving = false

    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()

            VStack(spacing: 6) {
                topBar
                feeds
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let toast {
                VStack {
                    Spacer()
                    Toast(text: toast, systemImage: toastIcon).padding(.bottom, 200)
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
        .onChange(of: settings.mode) { _, _ in restart() }
        .onChange(of: settings.side) { _, _ in restart() }
        .onChange(of: settings.quality) { _, _ in restart() }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings)
        }
        .sheet(isPresented: $review.isPresented) {
            ReviewPromptView(lang: lang)
        }
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
                                                             : AnyShapeStyle(Color.white.opacity(0.08))))
            }

            Spacer()

            qualityMenu

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
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
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .disabled(engine.isRecording)
    }

    // MARK: - Feeds (stacked)

    private var feeds: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                feedCell(port: engine.portA, index: 0, size: geo.size)
                feedCell(port: engine.portB, index: 1, size: geo.size)
            }
        }
    }

    @ViewBuilder
    private func feedCell(port: AVCaptureInput.Port?, index: Int, size: CGSize) -> some View {
        let h = (size.height - 6) / 2
        ZStack {
            switch engine.status {
            case .running:
                FeedPreview(session: engine.session, port: port)
            case .simulator:
                PreviewPlaceholder(systemImage: index == 0 ? "camera.viewfinder" : "camera.rotate",
                                   text: L.t("simulator_note", lang))
            case .denied:
                deniedCell
            case .unsupported:
                PreviewPlaceholder(systemImage: "exclamationmark.triangle",
                                   text: L.t("multicam_unsupported", lang))
            default:
                PreviewPlaceholder(systemImage: "camera", text: "")
            }
            if settings.showGrid { GridOverlay() }
            feedBadge(index: index)
        }
        .frame(height: max(h, 80))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func feedBadge(index: Int) -> some View {
        let label: String
        switch settings.mode {
        case .frontBack:
            label = index == 0 ? L.t("side_back", lang) : L.t("side_front", lang)
        case .orientation:
            label = index == 0 ? "16:9" : "9:16"
        }
        return VStack {
            HStack {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                Spacer()
            }
            Spacer()
        }
        .padding(10)
    }

    private var deniedCell: some View {
        VStack(spacing: 12) {
            PreviewPlaceholder(systemImage: "lock.fill", text: L.t("cam_denied_body", lang))
            Button(L.t("open_settings", lang)) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(.black)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(LinearGradient.honey))
        }
    }

    // MARK: - Bottom controls

    private var controls: some View {
        HStack {
            modeSwitch
            Spacer()
            recordButton
            Spacer()
            if settings.mode == .orientation {
                sideSwitch
            } else {
                Color.clear.frame(width: 54, height: 54)
            }
        }
        .padding(.horizontal, 6)
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.snappy) {
                settings.mode = settings.mode == .frontBack ? .orientation : .frontBack
            }
        } label: {
            Image(systemName: settings.mode.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.white.opacity(0.08)))
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
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .disabled(engine.isRecording)
    }

    private var recordButton: some View {
        VStack(spacing: 6) {
            Button { toggleRecord() } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 4)
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
        // Evaluate the 24h review prompt shortly after the UI settles.
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
                // Small grace period so the writers finish flushing to disk.
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
