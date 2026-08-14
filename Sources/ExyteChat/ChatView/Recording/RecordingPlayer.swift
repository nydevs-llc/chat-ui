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

    /// Состояние воспроизведения, адресованное конкретной записи.
    ///
    /// Существует РЯДОМ с полями выше, а не вместо них: тот же `RecordingPlayer`
    /// обслуживает бар ввода (предпрослушивание только что записанного), где
    /// плеер один и вопроса «чей это прогресс» не возникает. Контекст нужен
    /// только там, где плеер один, а строк много, — в ленте переписки.
    @Published private(set) var context: VoicePlaybackContext = .notLoaded

    /// Файл, заряженный в плеер прямо сейчас.
    var currentAssetURL: URL? { context.assetURL }

    // Дефект 2 (P10): было `AVAudioSession()` — приватный инстанс, не влияющий
    // на реальную сессию приложения. Все `setCategory`/`setActive` ниже были
    // no-op, первое воспроизведение работало только потому, что сессия
    // приложения и так была пригодна для playback. `.sharedInstance()` —
    // единственный объект, который реально на что-то влияет.
    private let audioSession = AVAudioSession.sharedInstance()
    var didPlayTillEnd = PassthroughSubject<Void, Never>()
    private var recording: Recording?

    /// Адрес файла, реально заряженного в `AVPlayer`.
    ///
    /// Не `recording?.url`: у записи URL может смениться (резолв), а заряжён в
    /// плеер по-прежнему прежний файл, пока `setupPlayer` не отработал.
    private var loadedAssetURL: URL?
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

    /// Старт уже идёт, но `playing` ещё не выставлен.
    ///
    /// `play()` при позиции у конца трека домматывает до нуля АСИНХРОННО и зовёт
    /// `startPlayback()` только из completion — а `playing = true` живёт внутри
    /// `startPlayback()`. Между входом в `play()` и приходом completion флаг
    /// `playing` всё ещё `false`, поэтому `guard !playing` пропускает второй
    /// вызов: планируются два seek'а, оба зовут `startPlayback()`, и запись
    /// звучит дважды внахлёст. Этот флаг закрывает окно.
    private var isStartingPlayback = false

    deinit {
        // Речь про ФОЛБЭЧНЫЙ путь — потребителей вне ленты переписки
        // (карточка-цитата публикации, бар ввода, превью), где плеер по-прежнему
        // живёт в `@StateObject` строки. Там плеер переживает свою вьюху: SwiftUI
        // пересоздаёт её при переотдаче сообщения (например, когда доезжает
        // резолвнутый URL), и `@StateObject` предыдущего поколения уничтожается.
        // Без явной паузы осиротевший `AVPlayer` доигрывает запись до конца —
        // звук идёт, а управлять им уже нечем: на экране новый плеер с
        // `playing == false`.
        //
        // В ленте переписки этого сценария больше нет: плеер там один и
        // принадлежит координатору списка (`SonataUIList.Coordinator.voicePlayer`),
        // переживает переконфигурацию ячеек и освобождается только вместе со
        // всем списком. Пауза на разрушении остаётся верной и для него — просто
        // случается на порядок реже.
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        removeAllNotificationObservers()
    }

    // MARK: - Public Methods

    /// Безусловный старт — для отложенного запуска, где намерение уже известно.
    ///
    /// `togglePlay` здесь семантически неверен: он ТУМБЛЕР, и на уже играющем
    /// плеере ставит паузу. Отложенный старт может прийти повторно (перерисовка,
    /// пересоздание строки, повторный `onAppear`), и тумблер в этом месте
    /// глушил бы только что запущенное воспроизведение.
    func startPlaying(_ recording: Recording) {
        if self.recording?.url != recording.url {
            self.recording = recording
            if let url = recording.url {
                setupPlayer(for: url, trackDuration: recording.duration)
            }
        }
        guard !playing else { return }
        play()
    }

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
        // Снимаем и «старт в полёте»: пауза во время асинхронного seek'а иначе
        // оставила бы флаг поднятым навсегда и заблокировала все следующие play().
        isStartingPlayback = false
        player?.pause()
        playing = false
        refreshContext()
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
        // `pause()` выше зовётся только при `playing` — а сброс может прийти и
        // посреди старта, когда `playing` ещё false. Снимаем флаг безусловно.
        isStartingPlayback = false
        recording = nil
        secondsLeft = 0.0
        progress = 0
        loadedAssetURL = nil
        refreshContext()
    }

    // MARK: - Private Methods

    private func setupPlayer(for url: URL, trackDuration: Double) {
        duration = trackDuration
        progress = 0.0
        secondsLeft = trackDuration
        loadedAssetURL = url
        refreshContext()
        removeAllNotificationObservers()
        // Обнулить ссылку недостаточно: наблюдатель остаётся зарегистрированным
        // в старом плеере и продолжает тикать. Снимаем его до замены item'а.
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
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
            self.refreshContext()

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
        // Плеер надо ОСТАНОВИТЬ, а не только пометить флагом.
        //
        // Сюда приходит и наблюдатель времени, который ловит «почти конец»
        // (`duration - endOfTrackEpsilon`), то есть ДО реального конца файла —
        // `AVPlayer` в этот момент ещё играет. Раньше код лишь сбрасывал
        // `playing` и перематывал в ноль, а `seek(to: .zero)` на ИГРАЮЩЕМ плеере
        // означает «играй с начала»: запись звучала второй раз подряд, причём
        // кнопка оставалась в положении play, потому что флаг уже был `false`.
        player?.pause()
        playing = false
        progress = 0
        secondsLeft = duration
        refreshContext()
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
        guard !playing, !isStartingPlayback else { return }
        isStartingPlayback = true
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
        isStartingPlayback = false
        player?.play()
        playing = true
        refreshContext()
        NotificationCenter.default.post(name: .audioPlaybackStarted, object: self)
    }

    /// Единственная точка сборки контекста.
    ///
    /// Контекст ПРОИЗВОДЕН от полей воспроизведения — второй самостоятельный
    /// источник истины неизбежно разъехался бы с первым.
    private func refreshContext() {
        context = VoicePlaybackContext(
            assetURL: loadedAssetURL,
            progress: progress,
            secondsLeft: secondsLeft,
            isPlaying: playing
        )
    }

}

#if DEBUG
extension RecordingPlayer {
    /// Прямая установка состояния для юнит-тестов контекста.
    ///
    /// Существует только чтобы проверить связь «поля → контекст» без
    /// `AVPlayer`, симулятора и реального файла.
    func applyContextForTesting(
        assetURL: URL?,
        progress: Double,
        secondsLeft: Double,
        isPlaying: Bool
    ) {
        self.loadedAssetURL = assetURL
        self.progress = progress
        self.secondsLeft = secondsLeft
        self.playing = isPlaying
        refreshContext()
    }
}
#endif

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
            // Дефект 2, п.4 (P10 follow-up): именно от этого catch зависит,
            // будет ли слышен звук — `play()` вызывает эту функцию и
            // безусловно продолжает (`player?.play(); playing = true`), не
            // проверяя результат. Оставляем такое поведение (не блокируем
            // playback на любой ошибке сессии: часть таких ошибок исторически
            // не мешала реальному звуку, а жёсткий блок на каждый чих —
            // отдельная смена политики, шире этой узкой задачи), но
            // перестаём делать провал неотличимым от штатной работы: печатаем
            // с деталями И валим DEBUG/тестовую сборку через
            // `assertionFailure`, чтобы это гарантированно всплыло на QA/CI,
            // а не терялось в консоли рядом с шумом AVFoundation. В релизе
            // `assertionFailure` — no-op, поведение не меняется.
            print("RecordingPlayer: failed to switch audio session to .playback: \(error.localizedDescription)")
            assertionFailure("RecordingPlayer: setCategory(.playback)/setActive(true) failed: \(error)")
        }
    }

    func prepareForPlayback() {
        activateAudioSession()
        initializePlayer()
    }
}
