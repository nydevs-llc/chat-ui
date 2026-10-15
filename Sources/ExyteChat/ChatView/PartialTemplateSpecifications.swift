//
//  SwiftUIView.swift
//  
//
//  Created by Alisa Mylnikova on 06.12.2023.
//

import SwiftUI

public extension ChatView where MessageContent == EmptyView {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         draft: String,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         inputViewBuilder: @escaping InputViewBuilderClosure,
         messageMenuAction: MessageMenuActionClosure?,
         didChangeDraft: @escaping (String) -> Void,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.inputViewBuilder = inputViewBuilder
        self.messageMenuAction = messageMenuAction
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where InputViewContent == EmptyView {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         messageBuilder: @escaping MessageBuilderClosure,
         messageMenuAction: MessageMenuActionClosure?,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.messageBuilder = messageBuilder
        self.messageMenuAction = messageMenuAction
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where MenuAction == DefaultMessageMenuAction {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         messageBuilder: @escaping MessageBuilderClosure,
         inputViewBuilder: @escaping InputViewBuilderClosure,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.messageBuilder = messageBuilder
        self.inputViewBuilder = inputViewBuilder
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where MessageContent == EmptyView, InputViewContent == EmptyView {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         messageMenuAction: MessageMenuActionClosure?,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.messageMenuAction = messageMenuAction
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where InputViewContent == EmptyView, MenuAction == DefaultMessageMenuAction {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         messageBuilder: @escaping MessageBuilderClosure,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.messageBuilder = messageBuilder
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where MessageContent == EmptyView, MenuAction == DefaultMessageMenuAction {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         inputViewBuilder: @escaping InputViewBuilderClosure,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.inputViewBuilder = inputViewBuilder
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}

public extension ChatView where MessageContent == EmptyView, InputViewContent == EmptyView, MenuAction == DefaultMessageMenuAction {

    init(messages: [Message],
         showAvatars: Bool = true,
         chatType: ChatType = .conversation,
         replyMode: ReplyMode = .quote,
         didSendMessage: @escaping (DraftMessage) -> Void,
         reactionDelegate: ReactionDelegate? = nil,
         didChangeDraft: @escaping (String) -> Void,
         draft: String,
         groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactions = reactionDelegate.map(MessageReactionsConfiguration.init(delegate:))
    }
}
