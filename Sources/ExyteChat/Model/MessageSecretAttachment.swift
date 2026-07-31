//
//  MessageSecretAttachment.swift
//  Chat
//
//  Вложение «ответ на секрет»: цитата чужого секрета (вопрос + ответ владельца
//  анкеты), которая рисуется большой карточкой над пузырём сообщения.
//

import Foundation

public struct MessageSecretAttachment {
    public let id: Int
    public let question: String
    public let answer: String?
    public let voice: Voice?

    /// Слово-префикс accessibility-лейбла карточки («Секрет»).
    ///
    /// Форк не знает про каталог строк приложения и не носит своего, поэтому
    /// локализованные подписи приходят снаружи тем же каналом, что и `onPlay`.
    /// Дефолт английский — он же значение для демо-приложения форка.
    public let accessibilityTitle: String
    /// Хвост accessibility-лейбла для голосового ответа («Голосовой ответ»):
    /// саму запись VoiceOver прочитать не может, читаем её описание.
    public let voiceAnswerAccessibilityLabel: String

    /// Резолв короткоживящего URL живёт в приложении — форк не знает про файловый сервис.
    public var onPlay: ((String) -> Void)?

    /// Голос ФАКТИЧЕСКИ заиграл — на вход `fileId`, как и у `onPlay`.
    ///
    /// Нужен потому, что ближайшая доступная приложению точка — «резолв ссылки
    /// завершился» — врёт: на плохой сети ссылка приезжает, а звука может не быть.
    /// Момент старта знает только плеер внутри форка, он и зовёт это замыкание.
    ///
    /// Зовётся на каждый переход плеера в `playing`, то есть и на возобновление
    /// после паузы. Дедупликация — на стороне приложения (защёлка по `fileId`),
    /// потому что ячейки ленты сообщений переиспользуются и хранить защёлку
    /// внутри карточки бессмысленно.
    public var onPlaybackStarted: ((String) -> Void)?

    public struct Voice: Equatable, Hashable {
        public let fileId: String
        public let durationMs: Int
        public let waveform: [Double]
        /// ТРАНЗИЕНТНОЕ поле: ссылка, резолвнутая в рантайме.
        ///
        /// Почему оно есть здесь и почему его НЕТ в снапшоте вложения на бэкенде
        /// и в кеше: ссылка короткоживущая, вмороженная в снапшот протухнет и
        /// сломает воспроизведение на следующем открытии чата. Персистится только
        /// `fileId`; URL живёт ровно столько, сколько живёт эта вью-модель.
        ///
        /// `nil` → карточка показывает «тап для воспроизведения» и зовёт `onPlay(fileId)`.
        /// Приложение резолвит ссылку и переотдаёт сообщение с заполненным `url` →
        /// карточка играет штатным плеером с прогрессом волны.
        ///
        /// НЕ переносить в persistence и НЕ убирать отсюда — это разные слои.
        public let url: URL?

        public init(fileId: String, durationMs: Int, waveform: [Double], url: URL? = nil) {
            self.fileId = fileId
            self.durationMs = durationMs
            self.waveform = waveform
            self.url = url
        }

        /// Копия с резолвнутой ссылкой — то, что приложение кладёт в сообщение
        /// после ответа файлового сервиса.
        public func withResolvedURL(_ url: URL?) -> Voice {
            Voice(fileId: fileId, durationMs: durationMs, waveform: waveform, url: url)
        }
    }

    public init(
        id: Int,
        question: String,
        answer: String?,
        voice: Voice?,
        accessibilityTitle: String = "Secret",
        voiceAnswerAccessibilityLabel: String = "Voice answer",
        onPlay: ((String) -> Void)? = nil,
        onPlaybackStarted: ((String) -> Void)? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.voice = voice
        self.accessibilityTitle = accessibilityTitle
        self.voiceAnswerAccessibilityLabel = voiceAnswerAccessibilityLabel
        self.onPlay = onPlay
        self.onPlaybackStarted = onPlaybackStarted
    }

    /// Правило отображения: голос вытесняет текст. Текст остаётся в модели как
    /// фолбек и как источник превью для списка чатов/пуша.
    public var showsVoice: Bool { voice != nil }

    /// Копия с резолвнутой ссылкой на голос — приложение зовёт её из `onPlay`,
    /// получив короткоживущий URL, и переотдаёт сообщение в ленту.
    public func withResolvedVoiceURL(_ url: URL?) -> MessageSecretAttachment {
        MessageSecretAttachment(
            id: id,
            question: question,
            answer: answer,
            voice: voice?.withResolvedURL(url),
            accessibilityTitle: accessibilityTitle,
            voiceAnswerAccessibilityLabel: voiceAnswerAccessibilityLabel,
            onPlay: onPlay,
            onPlaybackStarted: onPlaybackStarted
        )
    }
}

// `onPlay` и `onPlaybackStarted` исключены из `==`/`hash`: замыкания несравнимы,
// а без исключения диффабл ленты сообщений сочтёт каждое сообщение изменившимся
// на каждом рендере. Accessibility-подписи, наоборот, сравниваются — это обычные
// строки, и смена языка обязана дойти до ячейки.
extension MessageSecretAttachment: Equatable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.question == rhs.question
            && lhs.answer == rhs.answer && lhs.voice == rhs.voice
            && lhs.accessibilityTitle == rhs.accessibilityTitle
            && lhs.voiceAnswerAccessibilityLabel == rhs.voiceAnswerAccessibilityLabel
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(question)
        hasher.combine(answer); hasher.combine(voice)
        hasher.combine(accessibilityTitle)
        hasher.combine(voiceAnswerAccessibilityLabel)
    }
}
