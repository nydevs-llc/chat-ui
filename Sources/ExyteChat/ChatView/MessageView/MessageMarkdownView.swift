//
//  MessageMarkdownView.swift
//  Chat
//
//  Created by Dolya on 10.07.2025.
//

import SwiftUI

public struct MessageMarkdownView: View {
    @Environment(\.chatTheme) private var theme

    let message: Message
    let inbound: Bool
    let isDeleted: Bool
    let onMentionTap: ((String) -> Void)?

    public init(
        message: Message,
        inbound: Bool,
        isDeleted: Bool,
        onMentionTap: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.inbound = inbound
        self.isDeleted = isDeleted
        self.onMentionTap = onMentionTap
    }

    public var body: some View {
        MessageTextView(
            text: message.text,
            messageUseMarkdown: true,
            inbound: inbound,
            anyLinkColor: theme.colors.anyLink,
            darkLinkColor: theme.colors.darkLink,
            isDeleted: isDeleted,
            isStreaming: message.isStreaming,
            onMentionTap: onMentionTap
        )
        .allowsHitTesting(false)
    }
}
