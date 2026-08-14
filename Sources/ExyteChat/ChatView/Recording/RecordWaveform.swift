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

    /// Запасной плеер — только для потребителей БЕЗ общего (карточка-цитата,
    /// превью). В ленте переписки он не используется: там играет общий.
    ///
    /// Остаётся `@StateObject`, и это безопасно ровно потому, что вне ленты
    /// ячеек нет и переконфигурации, которая его снесла бы, тоже нет.
    @StateObject private var fallbackPlayer = RecordingPlayer()

    /// Общий плеер переписки, если он есть.
    @Environment(\.sharedVoicePlayer) private var sharedPlayer

    /// Кто на самом деле играет.
    private var recordPlayer: RecordingPlayer { sharedPlayer ?? fallbackPlayer }

    /// Состояние воспроизведения С ТОЧКИ ЗРЕНИЯ ЭТОЙ записи.
    ///
    /// Здесь и происходит развязка, ради которой всё затевалось: общий плеер
    /// вещает одно состояние на всю ленту, а строка берёт его, только если
    /// заряжена именно её запись. Чужое — `notLoaded`, то есть явный сброс.
    /// Без этой фильтрации переиспользованная ячейка показывала бы прогресс
    /// предыдущего сообщения.
    ///
    /// Хранится в `@State`, а НЕ вычисляется из плеера на каждом проходе `body`.
    /// Разница принципиальная: плеер приходит через `@Environment`, а окружение
    /// не подписывает вьюху на `ObservableObject`. Вычисляемое свойство отдавало
    /// бы свежее значение только когда `body` и так пересчитывается по другой
    /// причине — то есть волна и таймер стояли бы на месте, пока по ленте не
    /// пройдёт посторонняя перерисовка. Подписка ниже кладёт сюда значение
    /// каждым тиком плеера, и это единственный источник движения.
    @State private var displayContext: VoicePlaybackContext = .notLoaded

    var recording: Recording

    var colorButton: Color
    var colorButtonBg: Color
    var colorWaveform: Color
    /// Предел ширины волны. `nil` — прежнее поведение: волна занимает всю
    /// доступную ширину. Задаётся там, где пузырь обязан обжимать содержимое
    /// (голосовая искра), — иначе `GeometryReader` внутри растягивает его.
    var maxWaveformWidth: CGFloat? = nil
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
    /// Сигнал снят с `displayContext.progress`, а НЕ с `isPlaying`, и это принципиально.
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
    /// `isPlaying`. Дедупликация — на стороне приложения, где она переживает
    /// переиспользование ячеек.
    ///
    /// Штатные голосовые сообщения параметр не передают: замыкание `nil`, и оба
    /// `onChange` ниже выходят по первому же `guard`, не трогая даже `@State`.
    var onPlaybackStarted: (() -> Void)? = nil

    /// Защёлка на одно проигрывание: `progress` тикает каждые 0.2 с, и без неё
    /// «старт» улетал бы десятками раз за трек.
    @State private var didReportPlaybackStart = false

    /// Что рисует кнопка play прямо сейчас. Единственный источник истины для
    /// иконки — см. `VoicePlaybackPhase`.
    ///
    /// Раньше состояние кнопки вычислялось из пары `displayContext.isPlaying` /
    /// `displayContext.progress`, и это был не промах в условии, а ошибка уровнем
    /// выше: обе величины описывают ВОСПРОИЗВЕДЕНИЕ, а спиннер — про ЗАГРУЗКУ,
    /// у которой в этой вьюхе владельца не было. Из-за этого «уже доиграли»
    /// (`playing == false, progress == 0` после перемотки в начало) выглядело
    /// ровно как «ещё не начали», и спиннер возвращался на доигранном треке,
    /// вися до срабатывания предохранителя. Теперь фаза хранится явно и меняется
    /// только по событиям, а «доиграли» — отдельное состояние `finished`.
    @State private var phase: VoicePlaybackPhase = .idle

    /// Таймер, который переводит фазу в `gaveUp`. Перезапускается на каждом
    /// входе в буферизацию, снимается при появлении звука.
    @State private var bufferingTimeoutTask: Task<Void, Never>?

    var duration: Int {
        let context = displayContext
        // `secondsLeft == 0` означает И «не начинали», И «доиграли» — в обоих
        // случаях верно показать полную длительность записи.
        let remaining = context.secondsLeft != 0 ? context.secondsLeft : recording.duration
        return max(Int(remaining), 0)
    }

    /// Единственная точка, где меняется фаза кнопки.
    ///
    /// Держим её одной функцией, чтобы переходы нельзя было раскидать по
    /// обработчикам и потерять: всё, что вьюха наблюдает, превращается в событие
    /// и уходит в `VoicePlaybackPhase.applying(_:)`, где переходы описаны
    /// исчерпывающе. Таймер предохранителя синхронизируется здесь же — так
    /// спиннер и таймер не могут разъехаться.
    private func send(_ event: VoicePlaybackEvent) {
        let next = phase.applying(event)
        guard next != phase else { return }
        phase = next
        syncBufferingTimeout(next.showsSpinner)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if phase.showsSpinner {
                    // Тот же визуальный язык, что у голосовых в публикациях
                    // (`VoicePreviewPillView.playButton`): круг остаётся на месте,
                    // меняется только его содержимое.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(colorButton)
                } else if phase.showsPauseIcon {
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
                // Тап — единственный сигнал, поднимающий спиннер после того, как
                // запись уже прослушали: намерение из приложения в `finished`
                // намеренно игнорируется (см. `VoicePlaybackPhase`).
                //
                // `isResolved` решает, будет ли спиннер вообще: готовый локальный
                // файл стартует практически мгновенно, и спиннер на нём успел бы
                // только моргнуть — это читается как дефект, а не как отзывчивость.
                send(.tapped(isResolved: recording.url != nil))
                if let onPlayTap {
                    onPlayTap()
                } else {
                    recordPlayer.togglePlay(recording)
                }
            })
            
            VStack(alignment: .leading, spacing: 5) {
                // Узкий контейнер требует ДВУХ вещей сразу, и одного `frame` мало.
                //
                // `adjustedSamples` без `addExtraDots` прореживает волну под
                // ширину ЭКРАНА, а не контейнера (см. комментарий там же), —
                // поэтому при одном лишь `frame` волна продолжала рисоваться во
                // всю ширину экрана и вылезала из пузыря: пунктир проходил под
                // кнопкой play. Прореживаем сами через `downsampled(_:fitting:)`,
                // ровно как предписывает контракт компонента, и только потом
                // ограничиваем рамкой.
                RecordWaveformPlaying(
                    samples: maxWaveformWidth.map {
                        RecordWaveformPlaying.downsampled(recording.waveformSamples, fitting: $0)
                    } ?? recording.waveformSamples,
                    progress: displayContext.progress,
                    color: colorWaveform,
                    addExtraDots: false
                )
                .applyIf(maxWaveformWidth != nil) {
                    $0.frame(maxWidth: maxWaveformWidth)
                }
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
        // Единственный источник движения волны и таймера.
        //
        // `@Environment` отдаёт ССЫЛКУ на плеер, но не подписывает вьюху на его
        // `@Published`. Подписываемся на сам `context` (а не на
        // `objectWillChange`): тот шлётся из `willSet`, то есть ДО записи, и по
        // нему пришлось бы читать значение отдельным проходом. Здесь значение
        // приезжает уже изменённым, фильтруется по своей записи и кладётся в
        // `@State` — дальше SwiftUI сам перерисовывает ровно те строки, у
        // которых оно реально поменялось (`VoicePlaybackContext: Equatable`,
        // чужие тики схлопываются в один и тот же `.notLoaded`).
        .onReceive(recordPlayer.$context) { context in
            displayContext = context.matching(recording.url)
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
            // Намерение, пережившее пересоздание строки, — по той же причине, что
            // и строкой выше: `onChange` ловит только ПЕРЕХОД, а новое поколение
            // вьюхи рождается сразу с поднятым намерением (оно живёт в приложении
            // по `file_id`). Перехода нет — спиннер бы не завёлся там, где тап
            // уже был.
            if pendingPlayAfterResolve?.wrappedValue == true {
                send(.pendingIntentObserved)
            }
        }
        .onChange(of: pendingPlayAfterResolve?.wrappedValue ?? false) { isPending in
            // Намерение подняло приложение (например, тап по кнопке-дублю в
            // карточке). Своё `send(.tapped:)` из жеста выше идемпотентно с этим:
            // повторный вход в `buffering` фазу не меняет.
            guard isPending else { return }
            send(.pendingIntentObserved)
        }
        .onChange(of: displayContext.progress) { progress in
            // Playhead поехал — единственное надёжное доказательство, что звук
            // реально идёт (`playing` поднимается и при протухшей ссылке).
            // Двигает и фазу кнопки, и метрику: у обеих один и тот же критерий.
            guard progress > 0 else { return }
            send(.progressAdvanced)

            // `onPlaybackStarted` в guard первым: у штатных голосовых он nil, и
            // ветка выходит здесь же, не трогая `@State` и не вызывая перерисовку.
            guard let onPlaybackStarted,
                  !didReportPlaybackStart,
                  displayContext.isPlaying else { return }
            didReportPlaybackStart = true
            onPlaybackStarted()
        }
        .onChange(of: displayContext.isPlaying) { isPlaying in
            // Плеер поднял/опустил `playing`. Сам по себе из буферизации не
            // выводит — там ждём движения playhead, — но на готовом файле именно
            // он переключает кнопку в паузу, не дожидаясь первого тика.
            send(isPlaying ? .playerDidStart : .playerDidPause)

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
        .onDisappear {
            cancelBufferingTimeout()
            send(.disappeared)
        }
        .onReceive(recordPlayer.didPlayTillEnd) { _ in
            // Трек доигран. Ради этого события и появился отдельный `finished`:
            // плеер сейчас перемотает в начало (`playing = false, progress = 0`),
            // и без явной фазы это состояние было бы неотличимо от «ещё не
            // начали» — спиннер возвращался бы на доигранном треке.
            send(.reachedEnd)

            // Фолбэк для очень коротких записей. Наблюдатель времени тикает раз
            // в 0.2 с, поэтому трек короче этого может дойти до конца, не дав ни
            // одного ненулевого `progress`, — звук прозвучал, а события бы не было.
            // Досмотр до конца сам по себе доказывает, что воспроизведение шло.
            guard let onPlaybackStarted, !didReportPlaybackStart else { return }
            didReportPlaybackStart = true
            onPlaybackStarted()
        }
    }

    /// Сколько крутим спиннер, прежде чем сдаться и вернуть треугольник.
    ///
    /// НЕ равно `VoiceMessagePlayerView.resolveTimeout` (18 с) сознательно: тот
    /// отмеряет бюджет всей цепочки резолва в приложении и живёт в невидимом
    /// намерении, а этот — видимая пользователем анимация. Спиннер, крутящийся
    /// 18 секунд, читается как зависание, то есть ровно как тот баг, который
    /// правка и убирает.
    private static let bufferingTimeout: TimeInterval = 6

    /// Приводит таймер сдачи в соответствие фазе: крутим спиннер — тикает,
    /// в любой другой фазе — снят. Зовётся из единственной точки (`send(_:)`),
    /// поэтому таймер и картинка разъехаться не могут.
    ///
    /// По истечении `bufferingTimeout` фаза уходит в `gaveUp`: спиннер гаснет,
    /// возвращается треугольник, повторный тап никто не запрещает.
    ///
    /// Гасит РОВНО картинку. Намерение (`pendingPlayAfterResolve`) не трогаем
    /// сознательно, и это важно: штатная буферизация длится секунду-две, а сюда
    /// мы попадаем, только когда что-то уже пошло не так. Это предохранитель, а
    /// не рядовая ветка, и вести себя он должен минимально — снять зависшую
    /// анимацию, ни во что больше не вмешиваясь.
    ///
    /// Снимать заодно намерение было бы вредно дважды. Во-первых, резолв в
    /// приложении к этому моменту жив и продолжается — файл, доехавший на 7-й
    /// секунде, штатно доиграет сам через `startPendingPlaybackIfNeeded`, и
    /// отменять это ради косметики незачем. Во-вторых, форк не знает, чем занято
    /// приложение, и гасить его состояние по таймеру собственной анимации — это
    /// решать за него, когда сдаваться. Для этого у приложения есть свой бюджет
    /// (`VoiceMessagePlayerView.resolveTimeout`, 18 с) и свой снекбар об ошибке.
    ///
    /// Идемпотентна: повторный вызов при уже идущем таймере ничего не делает —
    /// иначе отсчёт перезапускался бы на каждой перерисовке и отложил бы сдачу
    /// до бесконечности, обнулив весь смысл предохранителя.
    private func syncBufferingTimeout(_ buffering: Bool) {
        guard buffering else {
            cancelBufferingTimeout()
            return
        }
        guard bufferingTimeoutTask == nil else { return }
        startBufferingTimeout()
    }

    private func startBufferingTimeout() {
        bufferingTimeoutTask?.cancel()
        bufferingTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.bufferingTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            bufferingTimeoutTask = nil
            send(.bufferingTimedOut)
        }
    }

    private func cancelBufferingTimeout() {
        bufferingTimeoutTask?.cancel()
        bufferingTimeoutTask = nil
    }

    /// Отложенный старт: пользователь нажал play, когда файла ещё не было.
    ///
    /// Зовётся из двух мест — `onChange(of: recording.url)` (ссылка доехала в
    /// живую вьюху) и `onAppear` (вьюха пересоздана и родилась уже с готовым
    /// URL, поэтому перехода значения не будет). Идемпотентна: защёлка
    /// одноразовая, а `displayContext.isPlaying` отсекает повторный заход.
    private func startPendingPlaybackIfNeeded(url: URL?) {
        guard let url,
              pendingPlayAfterResolve?.wrappedValue == true,
              !displayContext.isPlaying else { return }
        // Гасим намерение ПЕРЕД стартом, а не после.
        //
        // Гард выше смотрит в `displayContext`, а не в поля плеера, и в ленте
        // это существенно: плеер там ОДИН на весь список. Сырой `playing`
        // означал бы «в переписке сейчас звучит хоть что-нибудь», и чужая
        // играющая запись глушила бы отложенный старт этой строки — тап
        // остался бы без звука ровно потому, что рядом играет соседнее
        // сообщение. Фильтрация по `recording.url` снимает вопрос: строка
        // видит только своё воспроизведение.
        //
        // Само же гашение намерения ПЕРЕД `startPlaying` остаётся необходимым.
        // Поколений вьюхи в момент переотдачи сообщения живо два: старое ещё не
        // снесено, новое уже появилось, — и `playing` поднимается только внутри
        // `startPlayback()`, уже после асинхронного seek'а, так что оба успевают
        // пройти гард. Общее у них ровно одно: намерение в приложении (по
        // `file_id`). Сняв его первым же действием, мы закрываем гонку для всех
        // поколений сразу.
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
    /// См. `RecordWaveformWithButtons.maxWaveformWidth`.
    var maxWaveformWidth: CGFloat? = nil

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
            maxWaveformWidth: maxWaveformWidth,
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
