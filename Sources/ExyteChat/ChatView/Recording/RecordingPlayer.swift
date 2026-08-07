//
//  RecordingPlayer.swift
//
//
//  Created by Alexandra Afonasova on 21.06.2022.
//

import Combine
import AVFoundation
import SwiftOGG

final class RecordingPlayer: ObservableObject {

    // MARK: - Properties

    @Published var playing = false
    @Published var duration: Double = 0.0
    @Published var secondsLeft: Double = 0.0
    @Published var progress: Double = 0.0

    // Дефект 2 (P10): было `AVAudioSession()` — приватный инстанс, не влияющий
    // на реальную сессию приложения. Все `setCategory`/`setActive` ниже были
    // no-op, первое воспроизведение работало только потому, что сессия
    // приложения и так была пригодна для playback. `.sharedInstance()` —
    // единственный объект, который реально на что-то влияет.
    private let audioSession = AVAudioSession.sharedInstance()
    var didPlayTillEnd = PassthroughSubject<Void, Never>()
    private var recording: Recording?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var loaderDelegate: CryptoResourceLoaderDelegate?
    private var cancellables = Set<AnyCancellable>()
    private var oggToM4aCache: [URL: URL] = [:]

    // Дефект 4 (P10): блочные подписки `addObserver(forName:object:queue:using:)`
    // возвращают непрозрачный токен — это ОН является наблюдателем перед
    // NotificationCenter, а не `self`. `removeObserver(self)` их не снимает,
    // поэтому при каждом `setupPlayer` (смена трека в той же ячейке) набор
    // подписок расширяется, никогда не сокращаясь. Храним токены и снимаем их
    // именно по ним.
    private var notificationTokens: [NSObjectProtocol] = []

    // Дефект 1 (P10): допуск на расхождение конца трека. Декодированный из OGG
    // m4a может по факту быть на десятки–сотни мс короче/длиннее заявленной
    // `duration`, поэтому наблюдатель времени должен ловить «почти конец», а не
    // ждать точного совпадения с `item.duration`.
    private let endOfTrackEpsilon: Double = 0.2

    deinit {
        removeAllNotificationObservers()
    }

    // MARK: - Public Methods

    func togglePlay(_ recording: Recording) {
        if self.recording?.url != recording.url {
            self.recording = recording
            if let url = recording.url {
                setupPlayer(for: url, trackDuration: recording.duration)
            }
        }
        if playing {
            pause()
        } else {
            play()
        }
    }

    func pause() {
        player?.pause()
        playing = false
    }

    func seek(to progress: Double) {
        let goalTime = duration * progress
        player?.seek(to: CMTime(seconds: goalTime, preferredTimescale: 10))
        if !playing {
            play()
        }
    }

    func reset() {
        if playing {
            pause()
        }
        recording = nil
        secondsLeft = 0.0
        progress = 0
    }

    // MARK: - Private Methods

    private func setupPlayer(for url: URL, trackDuration: Double) {
        duration = trackDuration
        progress = 0.0
        secondsLeft = trackDuration
        removeAllNotificationObservers()
        timeObserver = nil
        player?.replaceCurrentItem(with: nil)

        let playbackUrl = convertOGGIfNeeded(url)
        let playerItem: AVPlayerItem

        if let mimeType = recording?.mimeType,
           mimeType != "audio/ogg",
           let recording,
           let key = recording.key,
           let iv = recording.iv,
           let url = recording.url
        {
            let loaderDelegate = CryptoResourceLoaderDelegate(
                url: url,
                key: key,
                iv: iv)

            self.loaderDelegate = loaderDelegate

            let asset = AVURLAsset(url: loaderDelegate.localStreamingURL, options: [
                "AVURLAssetOutOfBandMIMETypeKey": mimeType
            ])

            asset.resourceLoader.setDelegate(
                loaderDelegate,
                queue: DispatchQueue.main
            )

            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: playbackUrl)
        }

        player = AVPlayer(playerItem: playerItem)

        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    prepareForPlayback()
                case .failed:
                    print("Failed to load item: \(String(describing: playerItem.error?.localizedDescription))")
                case .unknown:
                    print("Status is unknown. Waiting for updates.")
                @unknown default:
                    print("Unhandled status: \(status.rawValue)")
                }
            }
            .store(in: &cancellables)

        setupTimeObserver()
        setupNotificationCenterObservers(for: playerItem)
    }

    private func convertOGGIfNeeded(_ url: URL) -> URL {
        guard url.pathExtension.lowercased() == "ogg" ||
              recording?.mimeType == "audio/ogg" else {
            return url
        }
        if let cached = oggToM4aCache[url] {
            return cached
        }
        let m4aUrl = FileManager.tempDirPath
            .appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            try OGGConverter.convertOpusOGGToM4aFile(src: url, dest: m4aUrl)
            oggToM4aCache[url] = m4aUrl
            return m4aUrl
        } catch {
            print("OGG to M4A conversion failed: \(error.localizedDescription)")
            return url
        }
    }

    private func setupTimeObserver() {
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            guard let item = self.player?.currentItem, !item.duration.seconds.isNaN else { return }
            self.duration = item.duration.seconds
            self.progress = time.seconds / item.duration.seconds
            self.secondsLeft = (item.duration - time).seconds

            // Дефект 1 (P10): второй, независимый от нотификации источник
            // истины о конце трека. `AVPlayerItemDidPlayToEndTime` не приходит,
            // если декодированный из OGG m4a короче заявленной `duration` —
            // плеер упирается в реальный конец файла, не долетев до отметки,
            // которую ждёт нотификация, и `playing` зависает в `true` навсегда.
            // Периодический наблюдатель уже тикает каждые 0.2с и не зависит от
            // точности исходной длительности — используем его как страховку.
            if self.playing, item.duration.seconds.isFinite, item.duration.seconds > 0,
               time.seconds >= item.duration.seconds - self.endOfTrackEpsilon {
                self.handlePlaybackReachedEnd()
            }
        }
    }

    /// Единая точка «трек закончился» — вызывается и нотификацией, и
    /// наблюдателем времени, поэтому идемпотентна: второй вызов должен быть
    /// no-op, а не повторным сбросом уже сброшенного состояния.
    private func handlePlaybackReachedEnd() {
        guard playing else { return }
        playing = false
        progress = 0
        secondsLeft = duration
        // Completion, а не «выстрелил и забыл»: без него `play()` может
        // вызвать `player.play()` раньше, чем плеер физически домотает до
        // нуля — тогда следующий тап по play молча стартует с конца, откуда
        // звука уже нет (это и есть исходный дефект 1).
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.progress = 0
        }
        didPlayTillEnd.send()
    }

    private func play() {
        guard !playing else { return }
        // Категорию сессии выставляем СИНХРОННО и ровно перед стартом.
        //
        // `Recorder` оставляет сессию в `.record` — в этой категории вывод звука
        // выключен. Асинхронный `initializePlayer()` ставит `.playback` только
        // из `prepareForPlayback()`, а тот триггерится статусом `.readyToPlay`,
        // то есть заведомо ПОЗЖЕ этого `player.play()`. Предпрослушивание
        // только что записанного сообщения из-за этого стартовало немым.
        activatePlaybackSession()

        // Дефект 1, п.3 (P10): если позиция уже у конца трека (например,
        // `handlePlaybackReachedEnd` выставил `playing = false`, но seek ещё в
        // полёте, либо конец достигнут путём, который эту функцию не прошёл),
        // сначала домотать до нуля и запустить `play()` только из completion —
        // иначе `player.play()` стартует с конца молча, без звука.
        if let player, let item = player.currentItem,
           item.duration.seconds.isFinite, item.duration.seconds > 0,
           player.currentTime().seconds >= item.duration.seconds - endOfTrackEpsilon {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self else { return }
                self.progress = 0
                self.secondsLeft = self.duration
                self.startPlayback()
            }
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        player?.play()
        playing = true
        NotificationCenter.default.post(name: .audioPlaybackStarted, object: self)
    }

}

// MARK: - Observers

private extension RecordingPlayer {

    func setupNotificationCenterObservers(for playerItem: AVPlayerItem) {

        let startedToken = NotificationCenter.default.addObserver(
            forName: .audioPlaybackStarted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let sender = notification.object as? RecordingPlayer, sender !== self {
                self.pause()
            }
        }

        let recordingStartedToken = NotificationCenter.default.addObserver(
            forName: .recordingStarted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if notification.object is Recorder, self.playing {
                self.reset()
            }
        }

        let recordingStoppedToken = NotificationCenter.default.addObserver(
            forName: .recordingStopped,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.prepareForPlayback()
        }

        // Дефект 1 (P10): теперь единая точка выхода `handlePlaybackReachedEnd()`
        // — та же, что вызывает и наблюдатель времени в `setupTimeObserver`.
        // Обработчик идемпотентен (`guard playing`), поэтому какой из двух
        // сработает первым — не важно.
        let endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackReachedEnd()
        }

        notificationTokens = [startedToken, recordingStartedToken, recordingStoppedToken, endToken]
    }

    // Дефект 4 (P10): снимаем блочные подписки по токенам, а не по `self`
    // (см. комментарий у `notificationTokens`).
    func removeAllNotificationObservers() {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
    }
}

// MARK: - Session initialization

private extension RecordingPlayer {

    func initializePlayer() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.audioSession.setCategory(.playback)
                try self.audioSession.setMode(.default)

                if self.isUsingBuiltInSpeaker() {
                    try self.audioSession.overrideOutputAudioPort(.speaker)
                }
            } catch {
                self.handleAudioSessionError(error)
            }
        }
    }

     func isUsingBuiltInSpeaker() -> Bool {
        return audioSession.currentRoute.outputs.first?.portType == .builtInSpeaker
    }

     func handleAudioSessionError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("Audio session configuration failed: \(error.localizedDescription)")
            self.fallbackAudioConfiguration()
        }
    }

    func fallbackAudioConfiguration() {
        do {
            try audioSession.setCategory(.playback, mode: .default)
        } catch let error {
            print("Fallback configuration failed with error: \(error.localizedDescription)")
        }
    }

     func activateAudioSession() {
        do {
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    /// Синхронно переводит сессию в `.playback` и активирует её.
    ///
    /// Отдельно от `initializePlayer()` именно потому, что тот асинхронный:
    /// на пути «записал → нажал play» между `player.play()` и уходом работы на
    /// глобальную очередь есть окно, в котором категория ещё `.record`, и звука
    /// нет. Здесь платим за синхронный вызов на главном потоке — но только в
    /// момент старта воспроизведения, а не на каждом кадре.
    ///
    /// `overrideOutputAudioPort` сюда не переносим: он валиден только для
    /// `.playAndRecord`, в `.playback` бросает `-50` и увёл бы нас в
    /// `handleAudioSessionError` на ровном месте.
    func activatePlaybackSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to switch audio session to playback: \(error.localizedDescription)")
        }
    }

    func prepareForPlayback() {
        activateAudioSession()
        initializePlayer()
    }
}
