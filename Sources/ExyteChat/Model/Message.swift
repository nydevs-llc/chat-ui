//
//  Message.swift
//  Chat
//
//  Created by Alisa Mylnikova on 20.04.2022.
//

import SwiftUI

// `MessagePublicationAttachment` переехал в собственный файл (Model/) — он оброс
// вопросом, голосом и правилом рендера и в шапке Message.swift больше не помещается.

public struct Message: Identifiable, Hashable {

    public enum Status: Equatable, Hashable {
        case sending
        case sent
        case received
        case read
        case error(DraftMessage)

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .sending:
                return hasher.combine("sending")
            case .sent:
                return hasher.combine("sent")
            case .received:
                return hasher.combine("received")
            case .read:
                return hasher.combine("read")
            case .error:
                return hasher.combine("error")
            }
        }

        public static func == (lhs: Message.Status, rhs: Message.Status) -> Bool {
            switch (lhs, rhs) {
            case (.sending, .sending):
                return true
            case (.sent, .sent):
                return true
            case (.received, .received):
                return true
            case (.read, .read):
                return true
            case ( .error(_), .error(_)):
                return true
            default:
                return false
            }
        }
    }

    public var id: String
    public var user: User
    public var status: Status?
    public var createdAt: Date

    public var text: String
    public var attachments: [Attachment]
    public var reactions: [Reaction]
    public var recording: Recording?
    public var replyMessage: ReplyMessage?
    public var isEncrypted: Bool
    public var isDeleted: Bool
    public var publicationAttachment: MessagePublicationAttachment?
    /// Разрешение воспроизведения голосового СООБЩЕНИЯ (не карточки-цитаты).
    ///
    /// Задано — форк сам ничего не качает: `recording.url` приезжает уже готовым
    /// локальным файлом из приложения. Не задано — прежнее поведение.
    /// Из `==`/`hash` исключено намеренно, см. `MessageVoicePlayback`.
    public var voicePlayback: MessageVoicePlayback?
    public var triggerRedraw: UUID?
    public var isStreaming: Bool

    public var type: MessageType

    public init(id: String,
                user: User,
                status: Status? = nil,
                createdAt: Date = Date(),
                text: String = "",
                attachments: [Attachment] = [],
                reactions: [Reaction] = [],
                recording: Recording? = nil,
                replyMessage: ReplyMessage? = nil,
                type: MessageType = .text,
                isEncrypted: Bool = false,
                isDeleted: Bool = false,
                publicationAttachment: MessagePublicationAttachment? = nil,
                voicePlayback: MessageVoicePlayback? = nil,
                isStreaming: Bool = false) {

        self.id = id
        self.user = user
        self.status = status
        self.createdAt = createdAt
        self.text = text
        self.attachments = attachments
        self.reactions = reactions
        self.recording = recording
        self.replyMessage = replyMessage
        self.type = type
        self.isEncrypted = isEncrypted
        self.isDeleted = isDeleted
        self.publicationAttachment = publicationAttachment
        self.voicePlayback = voicePlayback
        self.isStreaming = isStreaming
    }

    public static func makeMessage(
        id: String,
        user: User,
        status: Status? = nil,
        draft: DraftMessage) async -> Message {
            let attachments = await draft.medias.asyncCompactMap { media -> Attachment? in
                guard let thumbnailURL = await media.getThumbnailURL() else {
                    return nil
                }

                switch media.type {
                case .image:
                    return Attachment(id: UUID().uuidString, url: thumbnailURL, type: .image)
                case .video:
                    guard let fullURL = await media.getURL() else {
                        return nil
                    }
                    return Attachment(id: UUID().uuidString, thumbnail: thumbnailURL, thumbnailData: nil, full: fullURL, type: .video)
                }
            }

            return Message(id: id, user: user, status: status, createdAt: draft.createdAt, text: draft.text, attachments: attachments, recording: draft.recording, replyMessage: draft.replyMessage)
        }
}

extension Message {
    var time: String {
        DateFormatter.timeFormatter.string(from: createdAt)
    }
}

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.user == rhs.user &&
        lhs.status == rhs.status &&
        lhs.createdAt == rhs.createdAt &&
        lhs.text == rhs.text &&
        lhs.attachments == rhs.attachments &&
        lhs.reactions == rhs.reactions &&
        lhs.recording == rhs.recording &&
        lhs.replyMessage == rhs.replyMessage &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.triggerRedraw == rhs.triggerRedraw &&
        lhs.publicationAttachment == rhs.publicationAttachment
    }

    // `hash` задан явно и зеркалит `==`. Синтезированный вариант брал ВСЕ хранимые
    // поля, включая те, что `==` игнорирует (`type`, `isDeleted`, `isEncrypted`), —
    // то есть равные по `==` сообщения могли иметь разные хеши, что нарушает
    // контракт Hashable. Правило: поле, добавленное в `==`, добавляется и сюда.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(user)
        hasher.combine(status)
        hasher.combine(createdAt)
        hasher.combine(text)
        hasher.combine(attachments)
        hasher.combine(reactions)
        hasher.combine(recording)
        hasher.combine(replyMessage)
        hasher.combine(isStreaming)
        hasher.combine(triggerRedraw)
        hasher.combine(publicationAttachment)
    }
}

extension Message {
    public enum MessageType: String {
        case status
        case text
        case geo
        case file
        case document
        case url
        case call
    }
}

public struct Recording: Codable, Hashable {
    public var duration: Double
    public var waveformSamples: [CGFloat]
    public var url: URL?
    public var mimeType: String?
    public var key: Data?
    public var iv: Data?

    public init(
        duration: Double = 0.0,
        waveformSamples: [CGFloat] = [],
        url: URL? = nil,
        mimeType: String? = nil,
        key: Data? = nil,
        iv: Data? = nil
    ) {
        self.duration = duration
        self.waveformSamples = waveformSamples
        self.url = url
        self.mimeType = mimeType
        self.key = key
        self.iv = iv
    }
}

/// Внешнее разрешение источника голосового сообщения.
///
/// Зеркалит договорённость `MessagePublicationAttachment`: форк не знает про
/// файловый сервис, а ссылка на файл короткоживущая и в снапшот сообщения не
/// попадает — персистится только `file_id`. Поэтому резолв (ссылка → скачивание →
/// декод в m4a вне главного потока) живёт в приложении, а сюда приезжает уже
/// готовый локальный файл в `recording.url`.
///
/// Ровно то же самое делать внутри форка нельзя: `RecordingPlayer.convertOGGIfNeeded`
/// распознаёт ogg эвристикой и декодирует СИНХРОННО на главном потоке, то есть на
/// удалённом URL это `Data(contentsOf:)` по сети из `body`.
///
/// Замыкания и `fileId` в `Message.==`/`hash` НЕ участвуют: приложение пересобирает
/// их на каждом рендере ленты, и включение дребезжало бы список. Перерисовку по
/// приезду файла обеспечивает `recording.url`, который в `==` входит.
public struct MessageVoicePlayback {

    /// Идентификатор файла на бэкенде — единственное, что переживает кеш.
    public let fileId: String
    /// Тап по play, когда локального файла ещё нет. Форк в этот момент не играет.
    public let onPlay: (String) -> Void
    /// Звук фактически пошёл (playhead сдвинулся), а не «файл отдали плееру».
    public let onPlaybackStarted: ((String) -> Void)?
    /// Пользователь уже нажал play и ждёт файл — намерение со стороны приложения.
    ///
    /// Форк держит такую же защёлку в `@State`, но она умирает вместе со строкой
    /// списка, которую SwiftUI пересоздаёт как раз в момент прихода файла: новая
    /// вьюха рождается с готовым `url`, перехода значения нет, `onChange` не
    /// срабатывает — и тап пропадает. Приложение хранит намерение по `file_id`,
    /// поэтому оно переживает пересоздание, и вьюха стартует по `onAppear`.
    ///
    /// `false` у тех, кто про механику не знает: поведение прежнее.
    public let isPlayPending: Bool
    /// Погасить намерение на стороне приложения.
    ///
    /// Без него защёлка односторонняя: форк гасит только свою `@State`-половину,
    /// `isPlayPending` остаётся `true`, и отложенный старт срабатывает снова на
    /// каждой перерисовке — воспроизведение перезапускается по кругу.
    public let onPlayPendingResolved: ((String) -> Void)?

    public init(
        fileId: String,
        onPlay: @escaping (String) -> Void,
        onPlaybackStarted: ((String) -> Void)? = nil,
        isPlayPending: Bool = false,
        onPlayPendingResolved: ((String) -> Void)? = nil
    ) {
        self.fileId = fileId
        self.onPlay = onPlay
        self.onPlaybackStarted = onPlaybackStarted
        self.isPlayPending = isPlayPending
        self.onPlayPendingResolved = onPlayPendingResolved
    }
}

public struct ReplyMessage: Codable, Identifiable, Hashable {
    public static func == (lhs: ReplyMessage, rhs: ReplyMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.user == rhs.user &&
        lhs.createdAt == rhs.createdAt &&
        lhs.text == rhs.text &&
        lhs.attachments == rhs.attachments &&
        lhs.recording == rhs.recording
    }

    public var id: String
    public var user: User
    public var createdAt: Date

    public var text: String
    public var attachments: [Attachment]
    public var recording: Recording?

    public init(id: String,
                user: User,
                createdAt: Date,
                text: String = "",
                attachments: [Attachment] = [],
                recording: Recording? = nil) {

        self.id = id
        self.user = user
        self.createdAt = createdAt
        self.text = text
        self.attachments = attachments
        self.recording = recording
    }

    func toMessage() -> Message {
        Message(id: id, user: user, createdAt: createdAt, text: text, attachments: attachments, recording: recording)
    }
}

public extension Message {

    func toReplyMessage() -> ReplyMessage {
        ReplyMessage(id: id, user: user, createdAt: createdAt, text: text, attachments: attachments, recording: recording)
    }
}

public extension Message {
    var isDeliverableStatus: Bool {
        return [.sent, .received, .read].contains(status)
    }
}

import Foundation

public enum ReactionType: Codable, Equatable, Hashable, Sendable {
    case emoji(String)
    //case sticker(Image / Giphy / Memoji)
    //case other...
    
    var toString:String {
        switch self {
        case .emoji(let emoji):
            return emoji
        }
    }
    
    public var stringValue: String {
        switch self {
        case .emoji(let emoji):
            return emoji
        }
    }
}

public struct Reaction: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let user: User
    public let createdAt: Date
    public let type: ReactionType
    public var status: Status

    public init(id: String = UUID().uuidString, user: User, createdAt: Date = .now, type: ReactionType, status: Status = .sending) {
        self.id = id
        self.user = user
        self.createdAt = createdAt
        self.type = type
        self.status = status
    }
    
    var emoji: String? {
        switch self.type {
        case .emoji(let emoji): return emoji
        }
    }
}

extension Reaction {
    public enum Status: Codable, Equatable, Hashable, Sendable {
        case sending
        case sent
        case read
        case error(DraftReaction)
    }
}

extension Reaction {
    func isCurrentUser(myJid: String) -> Bool {
        user.id == myJid
    }
}


public struct DraftReaction: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let messageID: String
    public let createdAt: Date
    public let type: ReactionType

    public init(id: String = UUID().uuidString, messageID: String, createdAt: Date = .now, type: ReactionType) {
        self.id = id
        self.messageID = messageID
        self.createdAt = createdAt
        self.type = type
    }
}
