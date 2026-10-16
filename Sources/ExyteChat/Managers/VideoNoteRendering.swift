//
//  VideoNoteRendering.swift
//  Chat
//
//  Кружки в ленте. Конфигурация — значение, как у стикеров: приложение
//  отдаёт вью круга (плеер, кольцо прогресса, бейджи) и подписи, форк отвечает
//  за раскладку без пузыря (цитата, капсула времени, реакции, меню).
//

import SwiftUI

public struct ChatVideoNoteRendering {
    /// Содержимое круга заданного диаметра (приложение клипует его само).
    public var content: (Message, MessageVideoNote, CGFloat) -> AnyView
    /// Миниатюра кружка 32×32 для цитаты ответа. `nil` — круглая заглушка.
    public var replyThumbnail: (MessageVideoNote) -> AnyView?
    /// Подпись цитаты ответа на кружок («🎥 Видеосообщение»).
    public var replyTitle: String
    /// Подпись под кружком, удалённым модерацией (своё / чужое).
    public var removedCaption: (Bool) -> String
    /// Ячейка кружка показалась / ушла с экрана (автоплей, мини-плеер).
    public var onVisibilityChange: (Message, Bool) -> Void
    /// Меню сообщения открыто (`true`) / закрыто (`false`) для этого сообщения.
    public var onMenuVisibilityChange: (Message, Bool) -> Void

    public init(
        content: @escaping (Message, MessageVideoNote, CGFloat) -> AnyView,
        replyThumbnail: @escaping (MessageVideoNote) -> AnyView? = { _ in nil },
        replyTitle: String,
        removedCaption: @escaping (Bool) -> String = { _ in "" },
        onVisibilityChange: @escaping (Message, Bool) -> Void = { _, _ in },
        onMenuVisibilityChange: @escaping (Message, Bool) -> Void = { _, _ in }
    ) {
        self.content = content
        self.replyThumbnail = replyThumbnail
        self.replyTitle = replyTitle
        self.removedCaption = removedCaption
        self.onVisibilityChange = onVisibilityChange
        self.onMenuVisibilityChange = onMenuVisibilityChange
    }
}

private struct ChatVideoNoteRenderingKey: EnvironmentKey {
    static let defaultValue: ChatVideoNoteRendering? = nil
}

extension EnvironmentValues {
    /// Как и у стикеров: ячейки — отдельные корни SwiftUI, значение кладётся в
    /// окружение каждой ячейки явно (`SonataUIList`).
    var chatVideoNoteRendering: ChatVideoNoteRendering? {
        get { self[ChatVideoNoteRenderingKey.self] }
        set { self[ChatVideoNoteRenderingKey.self] = newValue }
    }
}

public extension Notification.Name {
    /// Голосовое форка начало играть. `userInfo["url"]` — локальный файл записи.
    static let chatVoicePlaybackStarted = Notification.Name("chatVoicePlaybackStarted")
    /// Голосовое доиграло до конца. `userInfo["url"]` — локальный файл записи.
    static let chatVoicePlaybackFinished = Notification.Name("chatVoicePlaybackFinished")
    /// Просьба приложения сыграть голосовое общим плеером ленты
    /// (последовательное воспроизведение). `object` — `Recording`.
    static let chatVoicePlayRequest = Notification.Name("chatVoicePlayRequest")
    /// Приложение начало воспроизведение со звуком (кружок): все плееры голосовых
    /// встают на паузу.
    static let chatMediaPlaybackStarted = Notification.Name("chatMediaPlaybackStarted")
}
