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
    /// Резолв короткоживущего URL живёт в приложении — форк не знает про файловый сервис.
    public var onPlay: ((String) -> Void)?

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

    public init(id: Int, question: String, answer: String?, voice: Voice?, onPlay: ((String) -> Void)? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.voice = voice
        self.onPlay = onPlay
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
            onPlay: onPlay
        )
    }
}

// `onPlay` исключён из `==`/`hash`: замыкание несравнимо, а без исключения
// диффабл ленты сообщений сочтёт каждое сообщение изменившимся на каждом рендере.
extension MessageSecretAttachment: Equatable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.question == rhs.question
            && lhs.answer == rhs.answer && lhs.voice == rhs.voice
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(question)
        hasher.combine(answer); hasher.combine(voice)
    }
}
