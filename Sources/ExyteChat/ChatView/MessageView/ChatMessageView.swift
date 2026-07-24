//
//  ChatMessageView.swift
//
//
//  Created by Alisa Mylnikova on 20.03.2023.
//

import SwiftUI

struct ChatMessageView<MessageContent: View>: View {
    
    typealias MessageBuilderClosure = ChatView<MessageContent, EmptyView, DefaultMessageMenuAction>.MessageBuilderClosure
    
    @ObservedObject var viewModel: ChatViewModel
    
    @Environment(\.chatTheme) private var theme
    
    var messageBuilder: MessageBuilderClosure?
    
    let row: MessageRow
    let chatType: ChatType
    let avatarSize: CGFloat
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let messageUseMarkdown: Bool
    let isDisplayingMessageMenu: Bool
    let showMessageTimeView: Bool
    let showAvatar: Bool
    let messageFont: UIFont
    let tapDocumentClosure: ChatView.TapDocumentClosure?
    let groupUsers: [User]
    
    var body: some View {
        Group {
            switch row.message.type {
            case .text, .file, .url, .document, .geo:
                // Кастомный `messageBuilder`, когда задан потребителем, рендерит и
                // текстовые типы — а не только `.call/.status`. Иначе редизайн-пузырь
                // (свои цвета/форма/статусы) не применялся к обычным сообщениям, и
                // работал лишь дефолтный `MessageView` с цветами из темы. Fallback —
                // штатный `MessageView`, если билдер не передан.
                if let messageBuilder {
                    messageBuilder(
                        row.message,
                        row.positionInUserGroup,
                        row.positionInMessagesSection,
                        row.commentsPosition,
                        { viewModel.messageMenuRow = row },
                        viewModel.messageMenuAction()
                    ) { attachment in
                        viewModel.presentAttachmentFullScreen(attachment)
                    }
                    .id(row.message.id)
                } else {
                    MessageView(
                        viewModel: viewModel,
                        message: row.message,
                        positionInUserGroup: row.positionInUserGroup,
                        positionInMessagesSection: row.positionInMessagesSection,
                        chatType: chatType,
                        avatarSize: avatarSize,
                        tapAvatarClosure: tapAvatarClosure,
                        messageUseMarkdown: messageUseMarkdown,
                        isDisplayingMessageMenu: isDisplayingMessageMenu,
                        showMessageTimeView: showMessageTimeView,
                        isGroup: showAvatar,
                        tapDocumentClosure: tapDocumentClosure,
                        groupUsers: groupUsers,
                        font: messageFont
                    )
                }

            case .call, .status:
                if let messageBuilder {
                    messageBuilder(
                        row.message,
                        row.positionInUserGroup,
                        row.positionInMessagesSection,
                        row.commentsPosition,
                        { viewModel.messageMenuRow = row },
                        viewModel.messageMenuAction()
                    ) { attachment in
                        viewModel.presentAttachmentFullScreen(attachment)
                    }
                    .id(row.message.id)
                } else {
                    EmptyView().id(row.message.id)
                }
            }
        }
    }
    
    private func shouldEnableReplyGesture(for message: Message) -> Bool {
        message.type != .call &&
        message.type != .status &&
        !message.isDeleted
    }
}
