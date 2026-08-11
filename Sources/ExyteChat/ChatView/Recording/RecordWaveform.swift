//
//  RecordWaveform.swift
//  
//
//  Created by Alisa Mylnikova on 14.03.2023.
//

import Combine
import SwiftUI

struct RecordWaveformWithButtons: View {

    @Environment(\.chatTheme) private var theme

    @StateObject var recordPlayer = RecordingPlayer()

    var recording: Recording

    var colorButton: Color
    var colorButtonBg: Color
    var colorWaveform: Color
    /// Внешний обработчик тапа по play. Когда задан — форк не проигрывает сам:
    /// URL короткоживущий и резолвится в приложении (карточка секрета).
    /// Штатные вызовы параметр не передают и работают как раньше.
    var onPlayTap: (() -> Void)? = nil
    /// Однократный триггер отложенного старта: пользователь уже нажал play, но
    /// ссылки тогда ещё не было. Как только `recording.url` приезжает,
    /// воспроизведение стартует само и флаг сбрасывается.
    ///
    /// Не «играть при появлении готового URL»: флаг поднимает только явный тап,
    /// поэтому ячейка, приехавшая на экран с уже готовой ссылкой, молчит.
    /// Штатные вызовы параметр не передают → `onChange` ниже ничего не делает.
    var pendingPlayAfterResolve: Binding<Bool>? = nil
    /// Звук ФАКТИЧЕСКИ пошёл: playhead сдвинулся с нуля.
    ///
    /// Сигнал снят с `recordPlayer.progress`, а НЕ с `playing`, и это принципиально.
    /// `RecordingPlayer.play()` делает `player?.play(); playing = true` без единой
    /// проверки статуса item'а: протухшая ссылка, `.failed` или провал декода дадут
    /// `playing == true` вообще без звука — ровно на плохой сети, ради которой
    /// метрика и заводится.
    ///
    /// `progress` же заполняет периодический наблюдатель времени, и только после
    /// `guard !item.duration.seconds.isNaN`: ненулевое значение означает, что asset
    /// разобран, длительность известна и playhead реально едет. Это ближайшее к
    /// «звук слышно», что доступно, — и достигается без единой правки плеера
    /// (`progress` уже `@Published`).
    ///
    /// Альтернативу `playerItem.status == .readyToPlay` не выбрал: статус живёт
    /// приватным полем `RecordingPlayer`, наружу не публикуется, и его пришлось бы
    /// прокидывать новым `@Published` — правка плеера ради сигнала слабее (готовность
    /// играть ≠ playhead поехал).
    ///
    /// Записи короче 0.2 с (шага наблюдателя времени) могут не дать ни одного тика
    /// `progress` — для них есть фолбэк на `didPlayTillEnd`: досмотр до конца сам
    /// по себе доказывает, что звук был. Так что «звук прозвучал, а события нет»
    /// не остаётся ни на какой длительности.
    ///
    /// Зовётся и на возобновление после паузы: защёлка снимается на входе в
    /// `playing`. Дедупликация — на стороне приложения, где она переживает
    /// переиспользование ячеек.
    ///
    /// Штатные голосовые сообщения параметр не передают: замыкание `nil`, и оба
    /// `onChange` ниже выходят по первому же `guard`, не трогая даже `@State`.
    var onPlaybackStarted: (() -> Void)? = nil

    /// Защёлка на одно проигрывание: `progress` тикает каждые 0.2 с, и без неё
    /// «старт» улетал бы десятками раз за трек.
    @State private var didReportPlaybackStart = false

    var duration: Int {
        return max(Int((recordPlayer.secondsLeft != 0 ? recordPlayer.secondsLeft : recording.duration)), 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if recordPlayer.playing {
                    theme.images.message.pauseAudio
                        .renderingMode(.template)
                } else {
                    theme.images.message.playAudio
                        .renderingMode(.template)
                }
            }
            .foregroundColor(colorButton)
            .viewSize(40)
            .circleBackground(colorButtonBg)
            .highPriorityGesture(TapGesture().onEnded {
                if let onPlayTap {
                    onPlayTap()
                } else {
                    recordPlayer.togglePlay(recording)
                }
            })
            
            VStack(alignment: .leading, spacing: 5) {
                RecordWaveformPlaying(samples: recording.waveformSamples, progress: recordPlayer.progress, color: colorWaveform, addExtraDots: false)
                Text(DateFormatter.timeString(duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(colorWaveform)
            }
        }
        .onChange(of: recording.url) { newURL in
            // Ссылка доехала после того, как пользователь нажал play, — стартуем
            // сами. Для штатных голосовых `recording.url` не меняется, а
            // `pendingPlayAfterResolve` не передан, так что путь мёртв.
            startPendingPlaybackIfNeeded(url: newURL)
        }
        .onAppear {
            // Тот же отложенный старт, но для случая, когда `onChange` физически
            // не может сработать: приложение переотдаёт сообщение с резолвнутым
            // URL, SwiftUI пересоздаёт строку, и НОВОЕ поколение вьюхи рождается
            // сразу с непустым `recording.url`. Перехода значения нет — значит
            // нет и `onChange`, а тап пользователя остался бы без звука.
            //
            // Условие то же самое, поэтому двойного старта не будет: защёлка
            // `pendingPlayAfterResolve` одноразовая и гасится внутри.
            startPendingPlaybackIfNeeded(url: recording.url)
        }
        .onChange(of: recordPlayer.progress) { progress in
            // `onPlaybackStarted` в guard первым: у штатных голосовых он nil, и
            // ветка выходит здесь же, не трогая `@State` и не вызывая перерисовку.
            guard let onPlaybackStarted,
                  !didReportPlaybackStart,
                  progress > 0,
                  recordPlayer.playing else { return }
            didReportPlaybackStart = true
            onPlaybackStarted()
        }
        .onChange(of: recordPlayer.playing) { isPlaying in
            // Новый заход воспроизведения — разрешаем отчёт снова (возобновление
            // после паузы считается новым стартом).
            //
            // Сбрасываем на ВХОДЕ в `playing`, а не на выходе, сознательно:
            // при выходе была бы гонка с `didPlayTillEnd` ниже. Плеер в обработчике
            // конца трека делает `playing = false`, а затем `didPlayTillEnd.send()`;
            // порядок доставки `onChange` и `onReceive` между собой не гарантирован,
            // и сброс «на выходе» мог бы успеть раньше — тогда фолбэк ниже счёл бы
            // отчёт неотправленным и продублировал событие на каждом обычном треке.
            guard onPlaybackStarted != nil, isPlaying else { return }
            didReportPlaybackStart = false
        }
        .onReceive(recordPlayer.didPlayTillEnd) { _ in
            // Фолбэк для очень коротких записей. Наблюдатель времени тикает раз
            // в 0.2 с, поэтому трек короче этого может дойти до конца, не дав ни
            // одного ненулевого `progress`, — звук прозвучал, а события бы не было.
            // Досмотр до конца сам по себе доказывает, что воспроизведение шло.
            guard let onPlaybackStarted, !didReportPlaybackStart else { return }
            didReportPlaybackStart = true
            onPlaybackStarted()
        }
    }

    /// Отложенный старт: пользователь нажал play, когда файла ещё не было.
    ///
    /// Зовётся из двух мест — `onChange(of: recording.url)` (ссылка доехала в
    /// живую вьюху) и `onAppear` (вьюха пересоздана и родилась уже с готовым
    /// URL, поэтому перехода значения не будет). Идемпотентна: защёлка
    /// одноразовая, а `recordPlayer.playing` отсекает повторный заход.
    private func startPendingPlaybackIfNeeded(url: URL?) {
        guard let url,
              pendingPlayAfterResolve?.wrappedValue == true,
              !recordPlayer.playing else { return }
        pendingPlayAfterResolve?.wrappedValue = false
        var resolved = recording
        resolved.url = url
        // Безусловный старт, НЕ тумблер: сюда можно прийти повторно (перерисовка
        // или новый `onAppear` до того, как намерение погасло на стороне
        // приложения), и `togglePlay` заглушил бы только что стартовавший звук.
        recordPlayer.startPlaying(resolved)
    }
}

/// Голосовое СООБЩЕНИЕ в пузыре.
///
/// Полный аналог `PublicationVoicePill` для карточки-цитаты, только источник —
/// `Message.voicePlayback`. Пока приложение не отдало локальный файл
/// (`recording.url == nil`), тап уходит наружу и запоминается как намерение;
/// как только файл приезжает, штатный плеер стартует сам.
///
/// Без `playback` (никто не передал разрешение) ведёт себя ровно как раньше:
/// `onPlayTap == nil`, играет `RecordingPlayer` по тому URL, что дали.
struct VoiceMessagePlayerView: View {

    let recording: Recording
    let playback: MessageVoicePlayback?

    let colorButton: Color
    let colorButtonBg: Color
    let colorWaveform: Color

    /// Поднимается ТОЛЬКО явным тапом при отсутствующем файле, гасится приездом
    /// файла либо таймаутом. Ячейка, приехавшая на экран с готовым файлом, молчит.
    @State private var pendingPlayAfterResolve = false
    @State private var resolveTimeoutTask: Task<Void, Never>?

    /// Столько ждём файл, прежде чем молча погасить намерение.
    /// Строго больше бюджета цепочки резолва в приложении (15 с) — плюс запас на
    /// переотдачу сообщения в ленту и реконфиг ячейки. Та же величина, что у
    /// карточки-цитаты (`MessagePublicationQuoteCardView`).
    private static let resolveTimeout: TimeInterval = 18

    /// Перехват тапа нужен ровно до приезда файла: дальше играет штатный плеер,
    /// а значит паузы и возобновления идут мимо приложения.
    private var playTapOverride: (() -> Void)? {
        guard let playback, recording.url == nil else { return nil }
        return {
            pendingPlayAfterResolve = true
            playback.onPlay(playback.fileId)
            startResolveTimeout()
        }
    }

    /// Намерение сыграть: своё (`@State`) ИЛИ пришедшее от приложения.
    ///
    /// Своё живёт ровно до пересоздания строки, а пересоздание случается как раз
    /// на приезде файла — поэтому в одиночку оно ненадёжно. Приложение держит то
    /// же намерение по `file_id`, и оно переживает любое число пересозданий.
    /// Запись `false` обязана гасить ОБЕ стороны. Иначе защёлка односторонняя:
    /// `get` продолжит возвращать `true` из `isPlayPending`, отложенный старт
    /// сработает снова на следующей же перерисовке — и так по кругу.
    private var pendingPlayBinding: Binding<Bool> {
        Binding(
            get: { pendingPlayAfterResolve || (playback?.isPlayPending ?? false) },
            set: { newValue in
                pendingPlayAfterResolve = newValue
                if !newValue, let playback, playback.isPlayPending {
                    playback.onPlayPendingResolved?(playback.fileId)
                }
            }
        )
    }

    var body: some View {
        RecordWaveformWithButtons(
            recording: recording,
            colorButton: colorButton,
            colorButtonBg: colorButtonBg,
            colorWaveform: colorWaveform,
            onPlayTap: playTapOverride,
            pendingPlayAfterResolve: playback != nil ? pendingPlayBinding : nil,
            onPlaybackStarted: playback.flatMap { playback in
                playback.onPlaybackStarted.map { report in { report(playback.fileId) } }
            }
        )
        .onChange(of: recording.url) { newURL in
            // Файл приехал — ждать больше нечего. Сам старт делает
            // `RecordWaveformWithButtons`, здесь только снимаем таймер.
            if newURL != nil { cancelResolveTimeout() }
        }
        .onDisappear {
            cancelResolveTimeout()
            pendingPlayAfterResolve = false
        }
    }

    private func startResolveTimeout() {
        resolveTimeoutTask?.cancel()
        resolveTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.resolveTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Молча: повторный тап никто не запрещает, а об ошибке пользователю
            // сообщает приложение (снекбар), не форк.
            pendingPlayAfterResolve = false
            resolveTimeoutTask = nil
        }
    }

    private func cancelResolveTimeout() {
        resolveTimeoutTask?.cancel()
        resolveTimeoutTask = nil
    }
}

struct RecordWaveformPlaying: View {

    var samples: [CGFloat] // 0...1
    var progress: CGFloat
    var color: Color
    var addExtraDots: Bool

    var maxLength: CGFloat {
        max((RecordWaveform.spacing + RecordWaveform.width) * CGFloat(samples.count) - RecordWaveform.spacing, 0)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                let adjusted = adjustedSamples(g.size.width)
                RecordWaveform(samples: adjusted, addExtraDots: addExtraDots)
                    .foregroundColor(color.opacity(0.4))
                RecordWaveform(samples: adjusted, addExtraDots: addExtraDots)
                    .foregroundColor(color)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: maxLength * progress, height: 2*RecordWaveform.maxSampleHeight)
                    }
            }
            .frame(height: RecordWaveform.maxSampleHeight)
        }
        .frame(height: RecordWaveform.maxSampleHeight)
        .applyIf(!addExtraDots) {
            $0.frame(width: maxLength)
        }
        .frame(maxWidth: addExtraDots ? .infinity : maxLength)
        .fixedSize(horizontal: !addExtraDots, vertical: true)
    }

    func adjustedSamples(_ width: CGFloat) -> [CGFloat] {
        // Обратите внимание: без `addExtraDots` ужимаем под ширину ЭКРАНА, а не
        // под фактическую. Для голосового сообщения это работает — пузырь и так
        // почти во всю ширину. Тому, кто рисует волну в узком контейнере, этого
        // мало: `maxLength` ниже фиксирует ширину по ИСХОДНОМУ числу сэмплов,
        // и контейнер разорвёт. Такой потребитель обязан проредить сам —
        // `downsampled(_:fitting:)` для этого и вынесен.
        Self.downsampled(samples, fitting: addExtraDots ? width : UIScreen.main.bounds.width)
    }

    /// Усреднение соседних сэмплов, пока волна не влезет в `width`.
    ///
    /// Вынесено из `adjustedSamples` без изменений в алгоритме, чтобы карточка
    /// публикации ужимала волну ровно так же, как это делает сам компонент, —
    /// иначе рисунок волны в карточке и в сообщении разошёлся бы.
    static func downsampled(_ samples: [CGFloat], fitting width: CGFloat) -> [CGFloat] {
        let maxSamples = Int(width / (RecordWaveform.width + RecordWaveform.spacing))
        // Ширины не хватает даже на один столбик: ужимать некуда, а цикл ниже
        // на `maxSamples == 0` не завершился бы никогда.
        guard maxSamples > 0 else { return samples }

        var adjusted = samples
        var temp = [CGFloat]()
        while adjusted.count > maxSamples {
            var i = 0
            while i < adjusted.count {
                if i == adjusted.count - 1 {
                    temp.append(adjusted[i])
                    break
                }

                temp.append((adjusted[i] + adjusted[i+1])/2)
                i+=2
            }
            adjusted = temp
            temp = []
        }
        return adjusted
    }
}

struct RecordWaveform: View {

    var samples: [CGFloat] // 0...1
    var addExtraDots: Bool

    static let spacing: CGFloat = 2
    static let width: CGFloat = 2
    static let maxSampleHeight: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: RecordWaveform.spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                    Capsule()
                        .frame(width: RecordWaveform.width, height: RecordWaveform.maxSampleHeight * CGFloat(s))
                }

                if addExtraDots {
                    ForEach(samples.count..<Int(g.size.width / (RecordWaveform.width + RecordWaveform.spacing)), id: \.self) { _ in
                        Capsule()
                            .viewSize(RecordWaveform.width)
                    }
                }
            }
            .frame(height: RecordWaveform.maxSampleHeight)
        }
        .frame(height: RecordWaveform.maxSampleHeight)
        .fixedSize(horizontal: !addExtraDots, vertical: true)
    }
}
