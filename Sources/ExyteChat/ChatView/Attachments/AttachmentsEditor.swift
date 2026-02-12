//
//  AttachmentsEditor.swift
//  Chat
//
//  Created by Alex.M on 22.06.2022.
//

import SwiftUI
// import ExyteMediaPicker  // Using MediaPickerFallback stubs
//import ActivityIndicatorView
import AVFoundation

struct AttachmentsEditor<InputViewContent: View>: View {

    typealias InputViewBuilderClosure = ChatView<EmptyView, InputViewContent, DefaultMessageMenuAction>.InputViewBuilderClosure

    @Environment(\.chatTheme) var theme
    @Environment(\.mediaPickerTheme) var pickerTheme

    @EnvironmentObject private var keyboardState: KeyboardState
    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @ObservedObject var inputViewModel: InputViewModel
    @ObservedObject private var mentionsViewModel = MentionsSuggestionsViewModel()
    
    var inputViewBuilder: InputViewBuilderClosure?
    var chatTitle: String?
    var messageUseMarkdown: Bool
    var orientationHandler: MediaPickerOrientationHandler
    var mediaPickerSelectionParameters: MediaPickerParameters?
    var availableInput: AvailableInputType

    @State private var seleсtedMedias: [Media] = []
    @State private var currentFullscreenMedia: Media?

    // Recording state
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var cameraMode: CameraMode = .photo

    // Camera state tracking
    @State private var isSwitchingCamera = false
    @State private var isTogglingFlash = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var isTorchOn = false

    // Optimized switching helpers
    @State private var switchWorkItems: [DispatchWorkItem] = []
    @State private var liveFeedReady: Bool = true   // controls liveCamera visibility while switching

    var showingAlbums: Bool {
        inputViewModel.mediaPickerMode == .albums
    }

    var body: some View {
        ZStack {
            mediaPicker

            if inputViewModel.showActivityIndicator {
//                ActivityIndicator()
            }
        }
        .onDisappear {
            // Ensure timers and pending tasks are cleaned up on leave
            stopRecordingTimer()
            cancelPendingSwitches()
        }
        .onChange(of: cameraMode) { newMode in
            // Stop the timer when returning to photo mode
            if newMode == .photo, isRecording { stopRecordingTimer() }
        }
    }
    
    // MARK: - Actions

    /// Safe torch toggle with minimal locking and optimistic UI state.
    private func toggleFlashSafe(_ toggleFlash: @escaping () -> Void) {
        guard !isTogglingFlash, !isRecording else { return }
        isTogglingFlash = true

        // Optimistically update local state to keep UI responsive
        isTorchOn.toggle()
        toggleFlash()

        isTogglingFlash = false
    }

    /// Debounced, time-staggered 3-attempt camera switch.
    /// Hides the live preview until the new feed is presumed ready.
    private func switchCameraSafe(_ switchCamera: @escaping () -> Void) {
        guard !isRecording, !isSwitchingCamera else {
            print("⚠️ Skip camera switch: isSwitchingCamera=\(isSwitchingCamera), isRecording=\(isRecording)")
            return
        }

        isSwitchingCamera = true
        liveFeedReady = false   // hide liveCamera until the pipeline stabilizes
        print("🔄 Camera switch started")

        // Flip expected position (UI state only; framework does the actual switch)
        let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        cameraPosition = newPosition
        print("📷 Expected camera position: \(newPosition == .back ? "back" : "front")")

        // Cancel any pending retries before scheduling new ones
        cancelPendingSwitches()

        // Schedule 3 attempts: t=0.00, 0.15, 0.30 (equivalent to your for-loop with spacing)
        let delays: [TimeInterval] = [0.0, 0.15, 0.30]
        for (idx, delay) in delays.enumerated() {
            let work = DispatchWorkItem {
                guard !isRecording else { return }
                switchCamera()
                print("🔁 switchCamera() attempt #\(idx + 1) (+\(String(format: "%.2f", delay))s)")

                // After the last attempt, wait a short tail to let the video pipeline rebuild,
                // then show the live feed again.
                if idx == delays.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        isSwitchingCamera = false
                        liveFeedReady = true
                        print("✅ Camera switch finished; live feed is ready")
                    }
                }
            }
            switchWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
    
    /// Cancel all pending switch attempts and reset flags.
    private func cancelPendingSwitches() {
        switchWorkItems.forEach { $0.cancel() }
        switchWorkItems.removeAll()
        // Do not change UI flags here unless you explicitly want to force-finish
        // a switch; flags are controlled in the scheduled tasks above.
    }

    var albumSelectionHeaderView: some View {
        ZStack {
            HStack {
                Button {
                    seleсtedMedias = []
                    inputViewModel.showPicker = false
                } label: {
                    Text("Скасувати")
                }
                Spacer()
            }

            HStack {
                Text("Останні")
                Image(systemName: "chevron.down")
                    .rotationEffect(Angle(radians: showingAlbums ? .pi : 0))
            }
            .onTapGesture {
                withAnimation {
                    inputViewModel.mediaPickerMode = showingAlbums ? .photos : .albums
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(.primary)
        .padding(.horizontal)
        .padding(.bottom, 5)
    }

    // MARK: - MediaPicker (UI unchanged; only the live preview visibility is controlled)

    var mediaPicker: some View {
        GeometryReader { g in
            MediaPicker(isPresented: $inputViewModel.showPicker) {
                seleсtedMedias = $0
                assembleSelectedMedia()
            } albumSelectionBuilder: { _, albumSelectionView, _ in
                ZStack {
                    VStack(spacing: 0) {
                        albumSelectionHeaderView
                            .padding(.top, g.safeAreaInsets.top > 0 ? g.safeAreaInsets.top : 20)
                            .padding(.bottom, 8)
                        albumSelectionView
                        Spacer()
                        inputView
                            .padding(.bottom, g.safeAreaInsets.bottom > 0 ? g.safeAreaInsets.bottom : 20)
                    }
                    .background(pickerTheme.main.pickerBackground)
                }
                .ignoresSafeArea()
            } cameraSelectionBuilder: { _, cancelClosure, cameraSelectionView in
                ZStack {
                    VStack(spacing: 0) {
                        headerCloseOnly(
                            topInset: g.safeAreaInsets.top > 0 ? g.safeAreaInsets.top : 20,
                            title: chatTitle,
                            onClose: {
                                cancelClosure()
                                cancelPendingSwitches()
                                stopRecordingTimer()
                            }
                        )

                        cameraSelectionView

                        cameraBottomControls(
                            safeBottomInset: g.safeAreaInsets.bottom,
                            onShowPreview: nil
                        )
                    }
                }
                .ignoresSafeArea()
            } cameraViewBuilder: { liveCamera, cancel, showPreview, takePhoto, startRecord, stopRecord, toggleFlash, switchCamera in
                GeometryReader { geometry in
                    ZStack {
                        // Keep the layout identical; only control live feed visibility during switching.
                        Group {
                            if liveFeedReady {
                                liveCamera
                            } else {
                                // Placeholder while switching; same footprint to avoid layout jumps.
                                Color.black
                            }
                        }
                        .ignoresSafeArea()

                        // TOP CONTROLS
                        VStack {
                            HStack {
                                Button(action: {
                                    cancel()
                                    cancelPendingSwitches()
                                    stopRecordingTimer()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .padding(.leading, 16)
                                .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top + 32 : 48)

                                Spacer()

                                Button(action: {
                                    toggleFlashSafe(toggleFlash)
                                }) {
                                    Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
//                                .disabled(isTogglingFlash || isRecording)
//                                .opacity((isTogglingFlash || isRecording) ? 0.5 : 1.0)
                                .disabled(true)
                                .opacity(0.0)
                                .padding(.trailing, 16)
                                .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top + 32 : 48)
                                .accessibilityLabel(isTorchOn ? "Turn flash off" : "Turn flash on")
                            }

                            Spacer()
                        }

                        // BOTTOM CONTROLS
                        VStack(spacing: 12) {
                            Spacer()

                            RecordingTimerView(elapsedTime: recordingTime, isRecording: isRecording)
                                .padding(.bottom, 4)

                            // Mode switch (Photo / Video)
                            HStack(spacing: 10) {
                                // Photo button - disabled if currently recording in video mode
                                modeChip(title: "ФОТО", active: cameraMode == .photo) {
                                    if !isRecording {   // ✅ prevent switching to photo while recording
                                        cameraMode = .photo
                                    }
                                }
                                .disabled(isRecording && cameraMode == .video)

                                // Video button (always available)
                                modeChip(title: "ВІДЕО", active: cameraMode == .video) {
                                    cameraMode = .video
                                }
                            }
                            .padding(.horizontal, 16)

                            HStack(alignment: .center, spacing: 40) {
                                Button(action: {
                                    if isRecording { stopRecordingTimer() }
                                    inputViewModel.mediaPickerMode = .albums
                                }) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .disabled(isRecording)
                                .opacity(isRecording ? 0.5 : 1.0)
                                .accessibilityLabel("Open gallery")
                    
                                ShutterButton(
                                    kind: cameraMode == .photo ? .photo : .video,
                                    isRecording: isRecording,
                                    isDisabled: (isSwitchingCamera || isTogglingFlash)
                                ) {
                                    // actionPhoto
                                    takePhoto()
                                } actionStartVideo: {
                                    startRecord()
                                    startRecordingTimer()
                                } actionStopVideo: {
                                    stopRecord()
                                    stopRecordingTimer()
                                }

                                Button(action: {
                                    switchCameraSafe(switchCamera)
                                }) {
                                    Image(systemName: cameraPosition == .back ? "camera.rotate" : "camera.rotate.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .disabled(isSwitchingCamera || isRecording)
                                .opacity((isSwitchingCamera || isRecording) ? 0.5 : 1.0)
                                .accessibilityLabel("Switch camera")
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom + 20 : 36)
                        }
                    }
                }
            }
            .didPressCancelCamera {
                inputViewModel.showPicker = false
                cancelPendingSwitches()
                stopRecordingTimer()
            }
            .currentFullscreenMedia($currentFullscreenMedia)
            .showLiveCameraCell()
            .setSelectionParameters(mediaPickerSelectionParameters)
            .pickerMode($inputViewModel.mediaPickerMode)
            .orientationHandler(orientationHandler)
            .background(pickerTheme.main.pickerBackground)
            .ignoresSafeArea(.all)
            .onChange(of: currentFullscreenMedia) { _ in
                assembleSelectedMedia()
            }
            .onChange(of: inputViewModel.showPicker) { newValue in
                let showFullscreenPreview = mediaPickerSelectionParameters?.showFullscreenPreview ?? true
                let selectionLimit = mediaPickerSelectionParameters?.selectionLimit ?? 1

                if selectionLimit == 1 && !showFullscreenPreview {
                    assembleSelectedMedia()
                    inputViewModel.send()
                }
                if !newValue {
                    // Reset state when picker is dismissed
                    stopRecordingTimer()
                    isSwitchingCamera = false
                    isTogglingFlash = false
                    cancelPendingSwitches()
                    liveFeedReady = true
                }
            }
        }
    }

    // MARK: - Helpers

    func assembleSelectedMedia() {
        if !seleсtedMedias.isEmpty {
            inputViewModel.attachments.medias = seleсtedMedias
        } else if let media = currentFullscreenMedia {
            inputViewModel.attachments.medias = [media]
        } else {
            inputViewModel.attachments.medias = []
        }
    }

    private func startRecordingTimer() {
        // Make sure we don't keep any pending switch tasks while recording
        cancelPendingSwitches()
        stopRecordingTimer()
        isRecording = true
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Keep state updates on the main thread
            DispatchQueue.main.async { self.recordingTime += 0.1 }
        }
    }

    private func stopRecordingTimer() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - UI Pieces

    private func headerCloseOnly(topInset: CGFloat, title: String? = nil, onClose: @escaping () -> Void) -> some View {
        ZStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(8)
                }
                Spacer()
            }
            if let title {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .padding(.bottom, 12)
        .background(Color(.systemBackground).opacity(0.9))
    }

    private func cameraBottomControls(safeBottomInset: CGFloat, onShowPreview: (() -> Void)?) -> some View {
        VStack(spacing: 8) {
            inputView
                .padding(.bottom, safeBottomInset > 0 ? safeBottomInset : 20)
        }
    }

    private func modeChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(active ? .white : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(active ? Color.dolyaBlue : Color.black.opacity(0.35))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording Timer View (camera style)
struct RecordingTimerView: View {
    let elapsedTime: TimeInterval
    let isRecording: Bool   // <- control visibility from parent

    @State private var blink = false

    var body: some View {
        Group {
            if isRecording {
                HStack(spacing: 8) {
                    // Blinking red dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(blink ? 0.25 : 1.0)
                        // start infinite blinking only while visible
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blink)

                    Text(timeString)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                .accessibilityLabel("Запис. Час \(timeString)")
                .transition(.opacity)                 // nice fade in/out
                .onAppear { blink = true }            // start blinking when shown
                .onDisappear { blink = false }        // stop blinking when hidden
            }
        }
        // Safety: if parent toggles 'isRecording' while still mounted
        .onChange(of: isRecording) { rec in
            if rec { blink = true } else { blink = false }
        }
    }

    private var timeString: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let milliseconds = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}


enum CameraMode { case photo, video }

extension AttachmentsEditor {
    @ViewBuilder
    var inputView: some View {
        Group {
            if let inputViewBuilder = inputViewBuilder {
                inputViewBuilder(
                    $inputViewModel.text,
                    inputViewModel.attachments,
                    inputViewModel.state,
                    .signature,
                    inputViewModel.inputViewAction()
                ) {
                    globalFocusState.focus = nil
                }
            } else {
                InputView(
                    mentionsViewModel: mentionsViewModel,
                    viewModel: inputViewModel,
                    inputFieldId: UUID(),
                    style: .signature,
                    availableInput: availableInput,
                    messageUseMarkdown: messageUseMarkdown
                )
                .padding(.horizontal, 16)
            }
        }
    }
}

struct ShutterButton: View {
    enum Kind { case photo, video }
    
    let kind: Kind
    let isRecording: Bool
    let isDisabled: Bool
    let actionPhoto: () -> Void
    let actionStartVideo: () -> Void
    let actionStopVideo: () -> Void
    
    // Apple-like sizes
    private let outerSize: CGFloat = 76
    private let innerSize: CGFloat = 62
    private let ringWidth: CGFloat = 5
    
    // Fixed layout size
    private let touchSize: CGFloat = 76
    
    @State private var pressed = false
    
    // Recording animation states
    @State private var morphProgress: CGFloat = 0
    @State private var recordPulse = false
    @State private var ripples = false
    @State private var ringGlow = false
    
    var body: some View {
        Button {
            guard !isDisabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if kind == .photo {
                actionPhoto()
            } else {
                isRecording ? actionStopVideo() : actionStartVideo()
            }
        } label: {
            ZStack {
                // Background black plate
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: outerSize, height: outerSize)
                
                // Outer ring (glow when recording)
                Circle()
                    .stroke(Color.white, lineWidth: ringWidth)
                    .frame(width: outerSize, height: outerSize)
                    .shadow(color: Color.red.opacity(isRecording ? (ringGlow ? 0.65 : 0.35) : 0),
                            radius: isRecording ? 8 : 0, x: 0, y: 0)
                    .scaleEffect(isRecording ? 1.04 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isRecording)
                
                // Ripple waves (optional - можете видалити якщо не потрібні)
                if kind == .video && isRecording {
                    Group {
                        Circle()
                            .stroke(Color.red.opacity(0.35), lineWidth: 2)
                            .frame(width: innerSize, height: innerSize)
                            .scaleEffect(ripples ? 1.6 : 1.0)
                            .opacity(ripples ? 0.0 : 0.6)
                        
                        Circle()
                            .stroke(Color.red.opacity(0.25), lineWidth: 2)
                            .frame(width: innerSize, height: innerSize)
                            .scaleEffect(ripples ? 2.0 : 1.2)
                            .opacity(ripples ? 0.0 : 0.5)
                    }
                }
                
                // Inner morphing core
                RecordMorphShape(
                    progress: kind == .video ? morphProgress : 0,
                    bigDiameter: innerSize,
                    smallSize: 34,
                    smallCorner: 8
                )
                .fill(kind == .photo ? Color.white : Color.red)
                .frame(width: innerSize, height: innerSize)
                .scaleEffect(isRecording && kind == .video ? (recordPulse ? 1.08 : 1.0) : (pressed ? 0.9 : 1.0))
            }
           
            .frame(width: touchSize, height: touchSize)
            .contentShape(Circle())
            .opacity(isDisabled ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: pressed)
            .onAppear { syncAnimationsWithState() }
            .onChange(of: isRecording) { _ in syncAnimationsWithState() }
        }
        .buttonStyle(ShutterButtonStyle(isPressed: pressed))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(accessibilityLabel)
    }
    
    private var accessibilityLabel: String {
        switch kind {
        case .photo: return "Зробити фото"
        case .video: return isRecording ? "Зупинити запис відео" : "Почати запис відео"
        }
    }
    
    // Keep animation flags in sync
    private func syncAnimationsWithState() {
        if kind == .video && isRecording {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                morphProgress = 1
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                recordPulse = true
            }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ripples = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                ringGlow = true
            }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                morphProgress = 0
            }
            recordPulse = false
            ripples = false
            ringGlow = false
        }
    }
}

// MARK: - Animatable morphing shape (circle -> rounded square)
private struct RecordMorphShape: Shape {
    var progress: CGFloat
    let bigDiameter: CGFloat
    let smallSize: CGFloat
    let smallCorner: CGFloat
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        let size = bigDiameter - (bigDiameter - smallSize) * progress
        let corner = (bigDiameter / 2) - ((bigDiameter / 2) - smallCorner) * progress
        
        let x = rect.midX - size / 2
        let y = rect.midY - size / 2
        let rrect = CGRect(x: x, y: y, width: size, height: size)
        return Path(roundedRect: rrect, cornerRadius: corner, style: .continuous)
    }
}

// MARK: - Button style (press feedback)
struct ShutterButtonStyle: ButtonStyle {
    let isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
    }
}
