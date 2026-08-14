//
//  VoicePlaybackPhaseTests.swift
//
//  Фаза кнопки play у голосового сообщения.
//

import XCTest
@testable import ExyteChat

final class VoicePlaybackPhaseTests: XCTestCase {

    private typealias Phase = VoicePlaybackPhase

    /// Трек, доигранный до конца: тап по неготовому файлу → звук → конец.
    private var afterEnd: Phase {
        Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.progressAdvanced)
            .applying(.reachedEnd)
    }

    /// Звук идёт прямо сейчас.
    private var playing: Phase {
        Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.progressAdvanced)
    }

    // MARK: - Регрессия: спиннер после конца трека

    /// Главный тест файла. После конца трека кнопка обязана показать треугольник
    /// СРАЗУ, а не спиннер до срабатывания предохранителя.
    ///
    /// Так баг и выглядел: трек доигрывал, `handlePlaybackReachedEnd` перематывал
    /// в ноль (`playing = false, progress = 0`), а условие спиннера читало эту
    /// пару как «ещё грузимся» — и крутило ~6 секунд, пока не срабатывал таймаут.
    func test_послеКонцаТрека_спиннерНеВозвращается() {
        XCTAssertEqual(afterEnd, .finished)
        XCTAssertFalse(afterEnd.showsSpinner, "После конца трека спиннера быть не должно")
        XCTAssertFalse(afterEnd.showsPauseIcon, "После конца трека кнопка — треугольник")
    }

    /// Второе лицо того же бага. Намерение (`pendingVoiceMessagePlays`) гасится
    /// только в `trackVoiceMessagePlayed`, а тот дедуплицирован — один раз на
    /// `file_id` за показ экрана. Значит после первого прослушивания намерение
    /// может остаться поднятым, и доверять ему здесь означало бы вернуть спиннер
    /// на доигранном треке.
    func test_залипшееНамерениеПослеКонца_неПоднимаетСпиннер() {
        let withIntent = afterEnd.applying(.pendingIntentObserved)

        XCTAssertEqual(withIntent, .finished)
        XCTAssertFalse(withIntent.showsSpinner, "Намерение после конца трека игнорируется")
    }

    /// Игнорирование не одноразовое: намерение приходит на каждой перерисовке.
    func test_повторноеНамерениеПослеКонца_тожеИгнорируется() {
        let twice = afterEnd
            .applying(.pendingIntentObserved)
            .applying(.pendingIntentObserved)

        XCTAssertEqual(twice, .finished)
    }

    /// Обратная сторона: явный тап обязан поднимать спиннер и после конца трека —
    /// иначе повторное прослушивание по неготовому файлу осталось бы без отклика.
    func test_тапПослеКонца_спиннерПоднимает() {
        XCTAssertEqual(afterEnd.applying(.tapped(isResolved: false)), .buffering)
    }

    /// Плеер после конца трека делает `seek(to: .zero)` с completion, который ещё
    /// раз обнуляет `progress`, и опускает `playing`. Порядок доставки `onChange`
    /// и `onReceive` не гарантирован — поздние сигналы не должны ничего менять.
    func test_позднийСигналПлеераПослеКонца_ничегоНеЛомает() {
        XCTAssertEqual(afterEnd.applying(.playerDidPause), .finished)
        XCTAssertEqual(afterEnd.applying(.bufferingTimedOut), .finished)
    }

    // MARK: - Загрузка

    func test_тапПоНеготовомуФайлу_показываетСпиннер() {
        let phase = Phase.idle.applying(.tapped(isResolved: false))

        XCTAssertEqual(phase, .buffering)
        XCTAssertTrue(phase.showsSpinner)
    }

    /// Готовый локальный файл стартует практически мгновенно — спиннер успел бы
    /// только моргнуть, а это читается как дефект, а не как отзывчивость.
    func test_тапПоГотовомуФайлу_спиннерНеПоказывает() {
        XCTAssertFalse(Phase.idle.applying(.tapped(isResolved: true)).showsSpinner)
    }

    /// `RecordingPlayer.play()` поднимает `playing` без проверки статуса item'а:
    /// протухшая ссылка даёт `playing == true` при полной тишине. Гасив спиннер
    /// по нему, мы показали бы паузу при тишине — ровно на плохой сети, ради
    /// которой спиннер и заводился.
    func test_playingБезЗвука_спиннерНеГасит() {
        let phase = Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.playerDidStart)

        XCTAssertEqual(phase, .buffering)
        XCTAssertTrue(phase.showsSpinner, "playing без движения playhead — ещё не звук")
    }

    func test_движениеPlayhead_гаситСпиннерИПоказываетПаузу() {
        XCTAssertEqual(playing, .playing)
        XCTAssertFalse(playing.showsSpinner)
        XCTAssertTrue(playing.showsPauseIcon)
    }

    // MARK: - Предохранитель

    func test_таймаутБуферизации_возвращаетТреугольник() {
        let phase = Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.bufferingTimedOut)

        XCTAssertEqual(phase, .gaveUp)
        XCTAssertFalse(phase.showsSpinner)
        XCTAssertFalse(phase.showsPauseIcon)
    }

    /// Предохранитель гасит картинку, но не намерение: резолв в приложении жив,
    /// и опоздавший файл доигрывает сам — кнопка обязана это отразить.
    func test_опоздавшийФайлПослеСдачи_показываетПаузу() {
        let phase = Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.bufferingTimedOut)
            .applying(.progressAdvanced)

        XCTAssertEqual(phase, .playing)
        XCTAssertTrue(phase.showsPauseIcon)
    }

    func test_таймаутВоВремяЗвука_ничегоНеМеняет() {
        XCTAssertEqual(playing.applying(.bufferingTimedOut), .playing)
    }

    /// Повторный тап после сдачи обязан снова показать спиннер — иначе вторая
    /// попытка выглядит как незасчитанный тап, то есть исходный дефект.
    func test_повторныйТапПослеСдачи_сноваПоказываетСпиннер() {
        let phase = Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.bufferingTimedOut)
            .applying(.tapped(isResolved: false))

        XCTAssertEqual(phase, .buffering)
        XCTAssertTrue(phase.showsSpinner)
    }

    /// Защёлка сдачи не должна пережить новую попытку по готовому файлу.
    func test_тапПоГотовомуПослеСдачи_снимаетЗащёлку() {
        let phase = Phase.idle
            .applying(.tapped(isResolved: false))
            .applying(.bufferingTimedOut)
            .applying(.tapped(isResolved: true))

        XCTAssertEqual(phase, .idle)
    }

    // MARK: - Пауза

    func test_тапВоВремяЗвука_ставитНаПаузу() {
        let paused = playing.applying(.tapped(isResolved: true))

        XCTAssertEqual(paused, .paused)
        XCTAssertFalse(paused.showsPauseIcon, "На паузе кнопка — треугольник")
        XCTAssertFalse(paused.showsSpinner, "Пауза — не загрузка")
    }

    /// Регресс: на паузе кнопка застревала на иконке «пауза», хотя звук стоял.
    ///
    /// `pause()` пересобирает контекст, а `progress` посреди трека остаётся
    /// НЕНУЛЕВЫМ — вьюха видела изменившееся значение и слала
    /// `progressAdvanced` уже после паузы. Позиция playhead ≠ движение
    /// playhead: осознанную паузу пользователя отменять ей нельзя.
    func test_позднийProgressAdvancedНаПаузе_неВозвращаетВИгру() {
        let paused = playing.applying(.tapped(isResolved: true))
        XCTAssertEqual(paused, .paused)

        let afterLateTick = paused.applying(.progressAdvanced)

        XCTAssertEqual(afterLateTick, .paused, "Пауза обязана пережить запоздавший тик прогресса")
        XCTAssertFalse(afterLateTick.showsPauseIcon, "Кнопка на паузе — треугольник, а не пауза")
    }

    /// Возобновление с паузы: файл уже локально готов, спиннера быть не должно.
    func test_возобновлениеСПаузы_безСпиннера() {
        let resumed = playing
            .applying(.tapped(isResolved: true))
            .applying(.playerDidStart)

        XCTAssertEqual(resumed, .playing)
        XCTAssertFalse(resumed.showsSpinner)
    }

    func test_намерениеНаПаузе_неЛоматИконку() {
        let paused = playing.applying(.tapped(isResolved: true))

        XCTAssertEqual(paused.applying(.pendingIntentObserved), .paused)
    }

    // MARK: - Жизненный цикл вьюхи

    /// Новое поколение вьюхи после переотдачи сообщения рождается сразу в
    /// буферизации: собственный `@State` умер, но намерение живёт в приложении.
    func test_намерениеПослеПересозданияВьюхи_поднимаетСпиннер() {
        let phase = Phase.idle.applying(.pendingIntentObserved)

        XCTAssertEqual(phase, .buffering)
        XCTAssertTrue(phase.showsSpinner)
    }

    /// Во время звука намерение уже ничего не поднимает: приложение гасит его по
    /// `onPlaybackStarted`, и гонка тут реальна.
    func test_намерениеВоВремяЗвука_неЛоматПаузу() {
        XCTAssertEqual(playing.applying(.pendingIntentObserved), .playing)
    }

    func test_уходСЭкрана_сбрасываетФазу() {
        XCTAssertEqual(Phase.idle.applying(.tapped(isResolved: false)).applying(.disappeared), .idle)
        XCTAssertEqual(afterEnd.applying(.disappeared), .idle, "Новый показ экрана начинается чистым")
    }

    // MARK: - Полный цикл

    /// Сценарий из видео целиком: тап → загрузка → звук → конец → повтор.
    /// Ни в одной точке спиннер не появляется там, где его быть не должно.
    func test_полныйЦикл_повторноеПрослушивание() {
        var phase = Phase.idle

        phase = phase.applying(.tapped(isResolved: false))
        XCTAssertTrue(phase.showsSpinner, "1. Загрузка — спиннер")

        phase = phase.applying(.playerDidStart).applying(.progressAdvanced)
        XCTAssertTrue(phase.showsPauseIcon, "2. Звук идёт — пауза")

        phase = phase.applying(.reachedEnd)
        XCTAssertFalse(phase.showsSpinner, "3. Доиграли — НЕ спиннер")
        XCTAssertFalse(phase.showsPauseIcon, "3. Доиграли — треугольник")

        phase = phase.applying(.pendingIntentObserved)
        XCTAssertFalse(phase.showsSpinner, "4. Залипшее намерение не крутит спиннер")

        // Второе прослушивание: файл уже локальный, спиннера быть не должно вовсе.
        phase = phase.applying(.tapped(isResolved: true))
        XCTAssertFalse(phase.showsSpinner, "5. Готовый файл — без спиннера")

        phase = phase.applying(.playerDidStart)
        XCTAssertTrue(phase.showsPauseIcon, "6. Играет снова — пауза")

        phase = phase.applying(.reachedEnd)
        XCTAssertFalse(phase.showsSpinner, "7. Второй конец — тоже треугольник")
    }
}
