//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
// import ExyteMediaPicker  // Using MediaPickerFallback stubs
import CoreLocation

final class InputViewModel: ObservableObject {

    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    @Published var state: InputViewState = .empty
    
    @Published var showAttachmentsSheet = false

    @Published var showPicker = false
    @Published var mediaPickerMode = MediaPickerMode.photos
    
    @Published var showFilePicker = false
    @Published var showLocationPicker: Bool = false

    @Published var showActivityIndicator = false
    @Published var mentions: [MentionedUser] = []
    @Published var caretPosition: Int = 0

    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?

    private var recorder = Recorder()

    private var saveEditingClosure: ((String) -> Void)?

    private var recordPlayerSubscription: AnyCancellable?
    private var playerStateSubscription: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()

    func onStart() {
        subscribeValidation()
        subscribePicker()
    }

    func onStop() {
        subscriptions.removeAll()
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            self?.attachments.editingMessage = nil
            self?.attachments.replyMessage = nil
            self?.showPicker = false
            self?.text = ""
            self?.saveEditingClosure = nil
            self?.attachments = InputViewAttachments()
            self?.subscribeValidation()
            self?.state = .empty
        }
    }

    func send() {
        recorder.stopRecording()
        recordingPlayer?.reset()
        sendMessage()
            .store(in: &subscriptions)
    }

    func edit(_ closure: @escaping (String) -> Void) {
        saveEditingClosure = closure
        state = .editing
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] in
            self?.inputViewActionInternal($0)
        }
    }

    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .photo:
            mediaPickerMode = .photos
            showPicker = true
        case .attach:
            showAttachmentsSheet = true
        case .document:
            showFilePicker = true
        case .location:
            showLocationPicker = true
        case .add:
            mediaPickerMode = .camera
        case .camera:
            mediaPickerMode = .camera
            showPicker = true
        case .send:
            send()
        case .recordAudioTap:
            state = recorder.isAllowedToRecordAudio ? .isRecordingTap : .waitingForRecordingPermission
            recordAudio()
        case .recordAudioHold:
            state = recorder.isAllowedToRecordAudio ? .isRecordingHold : .waitingForRecordingPermission
            recordAudio()
        case .recordAudioLock:
            state = .isRecordingTap
        case .stopRecordAudio:
            recorder.stopRecording()
            if let _ = attachments.recording {
                state = .hasRecording
            }
            recordingPlayer?.reset()
        case .deleteRecord:
            unsubscribeRecordPlayer()
            recorder.stopRecording()
            attachments.recording = nil
        case .playRecord:
            state = .playingRecording
            if let recording = attachments.recording {
                subscribeRecordPlayer()
                recordingPlayer?.togglePlay(recording)
            }
        case .pauseRecord:
            state = .pausedRecording
            recordingPlayer?.pause()
        case .saveEdit:
            saveEditingClosure?(text)
            reset()
        case .cancelEdit:
            reset()
        }
    }

    private func recordAudio() {
        if recorder.isRecording {
            return
        }
        Task { @MainActor in
            attachments.recording = Recording()
            let url = await recorder.startRecording { duration, samples in
                DispatchQueue.main.async { [weak self] in
                    self?.attachments.recording?.duration = duration
                    self?.attachments.recording?.waveformSamples = samples
                }
            }
            if state == .waitingForRecordingPermission {
                state = .isRecordingTap
            }
            attachments.recording?.url = url
        }
    }
    
    func bindToRecordingPlayerState() {
        guard let recordingPlayer else { return }
        
        playerStateSubscription?.cancel()
        
        playerStateSubscription = recordingPlayer.$playing
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    self.state = .playingRecording
                } else if self.state == .playingRecording {
                    self.state = .pausedRecording
                }
            }
    }
    
    func unbindRecordingPlayer() {
        if state == .playingRecording || state == .pausedRecording {
            recordingPlayer?.reset()
            state = .pausedRecording
        }
        
        playerStateSubscription = nil
    }

}

private extension InputViewModel {

    func validateDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard state != .editing else { return } // special case

            let trimmedText = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !trimmedText.isEmpty || !self.attachments.medias.isEmpty {
                self.state = .hasTextOrMedia
            } else if trimmedText.isEmpty,
                      self.attachments.medias.isEmpty,
                      self.attachments.recording == nil {
                self.state = .empty
            }
        }
    }

    func subscribeValidation() {
        $attachments.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)

        $text.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)
    }

    func subscribePicker() {
        $showPicker
            .sink { [weak self] value in
                if !value {
                    self?.attachments.medias = []
                }
            }
            .store(in: &subscriptions)
    }

    func subscribeRecordPlayer() {
        recordPlayerSubscription = recordingPlayer?.didPlayTillEnd
            .sink { [weak self] in
                self?.state = .hasRecording
            }
    }

    func unsubscribeRecordPlayer() {
        recordPlayerSubscription = nil
        if recordingPlayer?.playing == true {
            recordingPlayer?.reset()
        }
    }
}

private extension InputViewModel {
    
    func mapAttachmentsForSend() -> AnyPublisher<[Attachment], Never> {
        attachments.medias.publisher
            .receive(on: DispatchQueue.global())
            .asyncMap { media in
                guard let thumbnailURL = await media.getThumbnailURL(), let thumbnailData = await media.getThumbnailData() else {
                    return nil
                }

                switch media.type {
                case .image:
                    return Attachment(id: UUID().uuidString, url: thumbnailURL, type: .image)
                case .video:
                    guard let fullURL = await media.getURL() else {
                        return nil
                    }
                    return Attachment(id: UUID().uuidString, thumbnail: thumbnailURL, thumbnailData: thumbnailData, full: fullURL, type: .video)
                }
            }
            .compactMap {
                $0
            }
            .collect()
            .eraseToAnyPublisher()
    }

    func sendMessage() -> AnyCancellable {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedText = applyMentionTags(to: trimmedText)
        
        showActivityIndicator = true
        
        return mapAttachmentsForSend()
            .compactMap { [attachments] _ in
                DraftMessage(
                    text: formattedText,
                    medias: attachments.medias,
                    recording: attachments.recording,
                    replyMessage: attachments.replyMessage,
                    createdAt: Date()
                )
            }
            .sink { [weak self] draft in
                self?.didSendMessage?(draft)
                DispatchQueue.main.async { [weak self] in
                    self?.showActivityIndicator = false
                    self?.reset()
                }
            }
    }
}

extension Publisher {
    func asyncMap<T>(
        _ transform: @escaping (Output) async -> T
    ) -> Publishers.FlatMap<Future<T, Never>, Self> {
        flatMap { value in
            Future { promise in
                Task {
                    let output = await transform(value)
                    promise(.success(output))
                }
            }
        }
    }
}

// MARK: - Location Message
extension InputViewModel {
    func sendLocationMessage(_ location: CLLocationCoordinate2D) {
        guard isValidCoordinate(location) else {
            return
        }
        
        let geoLocationString = String(format: "geo:%.6f,%.6f", location.latitude, location.longitude)
        self.text = geoLocationString
        send()
    }
    
    private func isValidCoordinate(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude.isFinite && location.longitude.isFinite &&
        (-90...90).contains(location.latitude) &&
        (-180...180).contains(location.longitude)
    }
}

private extension InputViewModel {
    func applyMentionTags(to originalText: String) -> String {
        var result = originalText
        for mention in mentions {
            let mentionTag = "<mention>\(mention.snapshot) (\(mention.id))</mention>"
            result = result.replacingOccurrences(of: mention.snapshot, with: mentionTag)
        }
        return result
    }
}

extension InputViewModel {
    func addMention(_ mention: MentionedUser) {
        if !mentions.contains(mention) {
            mentions.append(mention)
        }
    }

    func onTextChanged(_ newText: String) {
        var updatedText = newText
        var updatedMentions: [MentionedUser] = []

        for mention in mentions {
            let snapshot = mention.snapshot

            if updatedText.contains(snapshot) {
                updatedMentions.append(mention)
            } else {
                updatedText = removeMentionText(snapshot, from: updatedText)
            }
        }

        if updatedText != text || updatedMentions != mentions {
            self.text = updatedText
            self.mentions = updatedMentions
        }
    }

    private func removeMentionText(_ snapshot: String, from text: String) -> String {
        var result = text

        for (index, char) in text.enumerated() where char == "@" {
            let startIndex = text.index(text.startIndex, offsetBy: index)
            let afterAt = text[startIndex...]

            var matchLength = 0
            for i in stride(from: snapshot.count, through: 2, by: -1) {
                let prefix = String(snapshot.prefix(i))
                if afterAt.hasPrefix(prefix) {
                    matchLength = i
                    break
                }
            }

            guard matchLength > 0 else { continue }

            let endIndex = text.index(startIndex, offsetBy: matchLength, limitedBy: text.endIndex) ?? text.endIndex
            let deleteRange = startIndex..<endIndex

            result.removeSubrange(deleteRange)
            result = result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        return result
    }
    
    var formattedText: String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return applyMentionTags(to: trimmedText)
    }
}
