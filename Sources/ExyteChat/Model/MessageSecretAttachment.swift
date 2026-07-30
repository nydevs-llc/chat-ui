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

        public init(fileId: String, durationMs: Int, waveform: [Double]) {
            self.fileId = fileId
            self.durationMs = durationMs
            self.waveform = waveform
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
