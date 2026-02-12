//
//  MessageView.swift
//  Chat
//
//  Created by Alex.M on 23.05.2022.
//

import SwiftUI
import MapKit

struct MessageView: View {

    @Environment(\.chatTheme) private var theme

    @ObservedObject var viewModel: ChatViewModel

    let message: Message
    let positionInUserGroup: PositionInUserGroup
    let positionInMessagesSection: PositionInMessagesSection
    let chatType: ChatType
    let avatarSize: CGFloat
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let messageUseMarkdown: Bool
    let isDisplayingMessageMenu: Bool
    let showMessageTimeView: Bool
    let isGroup: Bool
    let tapDocumentClosure: ChatView.TapDocumentClosure?
    let groupUsers: [User]
    
    @State var avatarViewSize: CGSize = .zero
    @State var statusSize: CGSize = .zero
    @State var timeSize: CGSize = .zero
    @State var bubbleSize: CGSize = .zero
    static let widthWithMedia: CGFloat = 204
    static let horizontalNoAvatarPadding: CGFloat = 16 //or 8
    static let horizontalAvatarPadding: CGFloat = 8
    static let horizontalTextPadding: CGFloat = 12
    static let horizontalAttachmentPadding: CGFloat = 1 // for multiple attachments
    static let statusViewSize: CGFloat = 14
    static let horizontalStatusPadding: CGFloat = 8
    static let horizontalBubblePadding: CGFloat = 70

    var font: UIFont

    enum DateArrangement {
        case hstack, vstack, overlay
    }

    var additionalMediaInset: CGFloat {
        message.attachments.count > 1 ? MessageView.horizontalAttachmentPadding * 2 : 0
    }

    var dateArrangement: DateArrangement {
        let timeWidth = timeSize.width + 10
        let textPaddings = MessageView.horizontalTextPadding * 2
        let widthWithoutMedia = UIScreen.main.bounds.width
        - (message.user.isCurrentUser ? MessageView.horizontalNoAvatarPadding : avatarViewSize.width)
        - statusSize.width
        - MessageView.horizontalBubblePadding
        - textPaddings

        let maxWidth = message.attachments.isEmpty ? widthWithoutMedia : MessageView.widthWithMedia - textPaddings
        let finalWidth = message.text.width(withConstrainedWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)
        let lastLineWidth = message.text.lastLineWidth(labelWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)
        let numberOfLines = message.text.numberOfLines(labelWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)

        if numberOfLines == 1, finalWidth + CGFloat(timeWidth) < maxWidth {
            return .hstack
        }
        if lastLineWidth + CGFloat(timeWidth) < finalWidth {
            return .overlay
        }
        return .vstack
    }

    var showAvatar: Bool {
        positionInUserGroup == .single
        || (chatType == .conversation && positionInUserGroup == .last)
        || (chatType == .comments && positionInUserGroup == .first)
    }

    var topPadding: CGFloat {
        if chatType == .comments { return 0 }
        return positionInUserGroup.isTop && !positionInMessagesSection.isTop ? 8 : 4
    }

    var bottomPadding: CGFloat {
        if chatType == .conversation { return 0 }
        return positionInUserGroup.isTop ? 8 : 4
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !message.user.isCurrentUser {
                avatarView
            }

            VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 2) {
                if !isDisplayingMessageMenu, let reply = message.replyMessage?.toMessage() {
                    replyBubbleView(reply)
                        .opacity(0.5)
                        .padding(message.user.isCurrentUser ? .trailing : .leading, 10)
                        .overlay(alignment: message.user.isCurrentUser ? .trailing : .leading) {
                            Capsule()
                                .foregroundColor(theme.colors.buttonBackground)
                                .frame(width: 2)
                        }
                }
                
                if !message.user.isCurrentUser && (positionInUserGroup == .single || (chatType == .conversation && positionInUserGroup == .first)) && isGroup {
                    Text(message.user.name)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .label.withAlphaComponent(0.7)))
                        .offset(x: 8.0)
                }
                
                bubbleView(message)
            }
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.trailing, message.user.isCurrentUser ? MessageView.horizontalNoAvatarPadding : 0)
        .padding(message.user.isCurrentUser ? .leading : .trailing, MessageView.horizontalBubblePadding)
        .frame(maxWidth: UIScreen.main.bounds.width, alignment: message.user.isCurrentUser ? .trailing : .leading)
    }

    @ViewBuilder
    func bubbleView(_ message: Message) -> some View {
        VStack(
            alignment: message.user.isCurrentUser ? .leading : .trailing,
            spacing: -bubbleSize.height / 3
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if !message.attachments.isEmpty {
                    attachmentsView(message)
                }

                if let pubAttachment = message.publicationAttachment {
                    MessagePublicationCardView(
                        attachment: pubAttachment,
                        isOutgoing: message.user.isCurrentUser
                    )
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                }

                if message.type == .geo {
                    VStack(alignment: .trailing, spacing: 8) {
                        locationView(message)
                    }
                }
                
                if !message.text.isEmpty && message.type != .document && message.type != .geo {
                    textWithTimeView(message)
                        .font(Font(font))
                }
                
                if let recording = message.recording {
                    VStack(alignment: .trailing, spacing: 8) {
                        recordingView(recording)
                        messageTimeView()
                            .padding(.bottom, 8)
                            .padding(.trailing, 12)
                    }
                }
                
                if message.type == .document {
                    VStack(alignment: .trailing, spacing: 8) {
                        documentView(message)
                            .highPriorityGesture(TapGesture().onEnded {
                                tapDocumentClosure?(message.user, message.id)
                            })
                        messageTimeView()
                            .padding(.bottom, 8)
                            .padding(.trailing, 12)
                    }
                }
            }
            .bubbleBackground(message, theme: theme)
            .zIndex(0)
            
            if !isDisplayingMessageMenu && !message.reactions.isEmpty && !message.isDeleted {
                reactionsView(message)
                    .zIndex(1)
            }
        }
        .applyIf(isDisplayingMessageMenu) {
            $0.frameGetter($viewModel.messageFrame)
        }
    }
    
    @ViewBuilder
    func replyBubbleView(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.user.name)
                .fontWeight(.semibold)
                .padding(.horizontal, MessageView.horizontalTextPadding)

            if !message.attachments.isEmpty {
                attachmentsView(message)
                    .padding(.top, 4)
                    .padding(.bottom, message.text.isEmpty ? 0 : 4)
            }

            if !message.text.isEmpty {
                MessageTextView(
                    text: message.text,
                    messageUseMarkdown: messageUseMarkdown,
                    inbound: !message.user.isCurrentUser,
                    anyLinkColor: theme.colors.textMyReply,
                    darkLinkColor: theme.colors.darkLink,
                    isDeleted: message.isDeleted,
                    onMentionTap: { id in
                        if let user = groupUsers.first(where: {
                            $0.id.components(separatedBy: "@").first == id
                        }) {
                            tapAvatarClosure?(user, message.id)
                        }
                    }
                )
                .padding(.horizontal, MessageView.horizontalTextPadding)
            }

            if let recording = message.recording {
                recordingView(recording)
            }
        }
        .font(.caption2)
        .padding(.vertical, 8)
        .frame(width: message.attachments.isEmpty ? nil : MessageView.widthWithMedia + additionalMediaInset)
        .bubbleBackground(message, theme: theme, isReply: true)
    }

    @ViewBuilder
    var avatarView: some View {
        if isGroup {
            Group {
                if showAvatar {
                    AvatarView(url: message.user.avatarURL, cachedImage: message.user.avatarCachedImage, avatarSize: avatarSize)
                        .contentShape(Circle())
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                tapAvatarClosure?(message.user, message.id)
                            }
                        )
                } else {
                    Color.clear.viewSize(avatarSize)
                }
            }
            .padding(.horizontal, MessageView.horizontalAvatarPadding)
            .sizeGetter($avatarViewSize)
        } else {
            Spacer()
                .frame(width: MessageView.horizontalTextPadding)
        }
    }

    @ViewBuilder
    func attachmentsView(_ message: Message) -> some View {
        AttachmentsGrid(attachments: message.attachments) {
            viewModel.presentAttachmentFullScreen($0)
        }
        .applyIf(message.attachments.count > 1) {
            $0
                .padding(.top, MessageView.horizontalAttachmentPadding)
                .padding(.horizontal, MessageView.horizontalAttachmentPadding)
        }
        .overlay(alignment: .bottomTrailing) {
            if message.text.isEmpty {
                messageTimeView(needsCapsule: true)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func textWithTimeView(_ message: Message) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            MessageTextView(
                text: message.text,
                messageUseMarkdown: messageUseMarkdown,
                inbound: !message.user.isCurrentUser,
                anyLinkColor: theme.colors.anyLink,
                darkLinkColor: theme.colors.darkLink,
                isDeleted: message.isDeleted,
                onMentionTap: { id in
                    if let user = groupUsers.first(where: { $0.id.components(separatedBy: "@").first == id }) {
                        tapAvatarClosure?(user, message.id)
                    }
                }
            )
            .fixedSize(horizontal: false, vertical: true)

            messageTimeView()
                .baselineNudgeDown(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    func recordingView(_ recording: Recording) -> some View {
        RecordWaveformWithButtons(
            recording: recording,
            colorButton: message.user.isCurrentUser ? theme.colors.myMessage : .white,
            colorButtonBg: message.user.isCurrentUser ? .white : theme.colors.myMessage,
            colorWaveform: message.user.isCurrentUser ? theme.colors.textDarkContext : theme.colors.textLightContext
        )
        .padding(.horizontal, MessageView.horizontalTextPadding)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    func documentView(_ message: Message) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .resizable()
                .foregroundStyle(message.user.isCurrentUser ? .white : theme.colors.buttonBackground)
                .scaledToFit()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text.components(separatedBy: "-").first ?? "")
                    .font(.body)
                    .lineLimit(1)
                Text(message.text.components(separatedBy: "-").last ?? "")
                    .font(.footnote)
                
            }
        }
        .padding(.horizontal, MessageView.horizontalTextPadding)
        .padding(.top, 8)
    }
}

public extension View {

    @ViewBuilder
    func bubbleBackground(_ message: Message, theme: ChatTheme, isReply: Bool = false) -> some View {
        let radius: CGFloat = !message.attachments.isEmpty ? 12 : 20
        let additionalMediaInset: CGFloat = message.attachments.count > 1 ? 2 : 0
        self
            .frame(width: message.attachments.isEmpty ? nil : MessageView.widthWithMedia + additionalMediaInset)
            .foregroundColor(message.user.isCurrentUser ? (isReply ? theme.colors.textMyReply : theme.colors.textDarkContext) : theme.colors.textLightContext)
            .background {
                if isReply || !message.text.isEmpty || message.recording != nil {
                    if message.user.isCurrentUser && !isReply {
                        ZStack {
                            // Base color
                            RoundedRectangle(cornerRadius: radius)
                                .foregroundColor(theme.colors.myMessage)
                            // Gradient from left
                            RoundedRectangle(cornerRadius: radius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.44, green: 0.31, blue: 0.98),
                                            Color(red: 0.44, green: 0.31, blue: 0.98).opacity(0)
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            
                            // Gradient from right
                            RoundedRectangle(cornerRadius: radius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.39, green: 0.36, blue: 1),
                                            Color(red: 0.44, green: 0.31, blue: 0.98).opacity(0)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: radius)
                            .foregroundColor(message.user.isCurrentUser ? theme.colors.myMessage : theme.colors.friendMessage)
                            .opacity(isReply ? 0.5 : 1)
                    }
                }
            }
            .cornerRadius(radius)
    }
}

// MARK: - Location View

extension MessageView {
    
    @ViewBuilder
    func locationView(_ message: Message) -> some View {
        let coordinates = parseCoordinates(from: message.text)
        let size = CGSize(width: min(UIScreen.main.bounds.width * 0.6, 260), height: 128)
        
        if let lat = coordinates?.latitude, let lon = coordinates?.longitude {
            ZStack {
                MessageMapView(latitude: lat, longitude: lon, snapshotSize: size)
                    .frame(width: size.width, height: size.height)
                    .cornerRadius(20)
                    .overlay(alignment: .bottomTrailing) {
                        messageTimeView(needsCapsule: true)
                            .padding(.bottom, 6)
                            .padding(.trailing, 6)
                    }
                
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            openMaps(latitude: lat, longitude: lon)
                        }
                    )
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    func parseCoordinates(from text: String) -> (latitude: Double, longitude: Double)? {
        let cleanText = text.replacingOccurrences(of: "geo:", with: "")
        let components = cleanText.split(separator: ";").first?.split(separator: ",").compactMap { Double($0) }
        
        if let lat = components?.first, let lon = components?.last {
            return (latitude: lat, longitude: lon)
        }
        return nil
    }
    
    func openMaps(latitude: Double, longitude: Double) {
        let url = URL(string: "http://maps.apple.com/?q=\(latitude),\(longitude)")!
        UIApplication.shared.open(url)
    }
}

extension MessageView {
    @ViewBuilder
    func messageTimeView(needsCapsule: Bool = false) -> some View {
        if showMessageTimeView {
            let spacing: CGFloat = {
                guard let status = message.status else { return -4 }
                if case .error = status { return 4 }
                return -4
            }()

            if message.isDeleted {
                timeOnly(needsCapsule: needsCapsule)
                    .sizeGetter($timeSize)
            } else {
                timeWithOptionalStatus(needsCapsule: needsCapsule, spacing: spacing)
                    .sizeGetter($timeSize)
            }
        }
    }
    
    @ViewBuilder
    private func timeOnly(needsCapsule: Bool) -> some View {
        if needsCapsule {
            CapsuleTimeContainer(
                isCurrentUser: message.user.isCurrentUser,
                theme: theme
            ) {
                MessageTimeText(
                    text: message.time,
                    isCurrentUser: message.user.isCurrentUser,
                    theme: theme, needsCapsule: needsCapsule
                )
            }
        } else {
            MessageTimeText(
                text: message.time,
                isCurrentUser: message.user.isCurrentUser,
                theme: theme, needsCapsule: needsCapsule
            )
        }
    }

    @ViewBuilder
    private func timeWithOptionalStatus(needsCapsule: Bool, spacing: CGFloat) -> some View {
        let content = HStack(spacing: spacing) {
            if message.user.isCurrentUser, let status = message.status {
                MessageStatusView(
                    status: status,
                    needsCapsule: needsCapsule,
                    colorSet: MessageStatusColorSet(
                        sending: theme.colors.myMessageTime,
                        sent: theme.colors.myMessageTime,
                        received: theme.colors.myMessageTime,
                        read: theme.colors.myMessageTime
                    ),
                    onRetry: {
                        if case let .error(draft) = status {
                            viewModel.sendMessage(draft)
                        }
                    }
                )
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                .sizeGetter($statusSize)
            }

            // MessageTimeText(
            //     text: message.time,
            //     isCurrentUser: message.user.isCurrentUser,
            //     theme: theme, needsCapsule: needsCapsule
            // )
            // .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] }
        }

        if needsCapsule {
            CapsuleTimeContainer(
                isCurrentUser: message.user.isCurrentUser,
                theme: theme
            ) { content }
        } else {
            content
        }
    }
}

//#if DEBUG
//struct MessageView_Preview: PreviewProvider {
//    static let stan = User(id: "stan", name: "Stan", avatarURL: nil, avatarCachedImage: nil, isCurrentUser: false)
//    static let john = User(id: "john", name: "John", avatarURL: nil, avatarCachedImage: nil, isCurrentUser: true)
//
//    static private var shortMessage = "Hi, buddy!"
//    static private var longMessage = "Hello hello hello hello hello hello hello hello hello hello hello hello hello\n hello hello hello hello d d d d d d d d"
//
//    static private var replyedMessage = Message(
//        id: UUID().uuidString,
//        user: stan,
//        status: .read,
//        text: longMessage,
//        attachments: [
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//        ]
//    )
//
//    static private var message = Message(
//        id: UUID().uuidString,
//        user: stan,
//        status: .read,
//        text: shortMessage,
//        replyMessage: replyedMessage.toReplyMessage()
//    )
//
//    static var previews: some View {
//        ZStack {
//            Color.yellow.ignoresSafeArea()
//
//            MessageView(
//                viewModel: ChatViewModel(),
//                message: replyedMessage,
//                positionInUserGroup: .single,
//                chatType: .conversation,
//                avatarSize: 32,
//                tapAvatarClosure: nil,
//                messageUseMarkdown: false,
//                isDisplayingMessageMenu: false,
//                showMessageTimeView: true,
//                isGroup: false,
//                tapDocumentClosure: nil,
//                font: UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))
//            )
//        }
//    }
//}
//#endif

private struct BaselineNudgeDown: ViewModifier {
    let points: CGFloat
    func body(content: Content) -> some View {
        content.alignmentGuide(.lastTextBaseline) { d in
            d[.lastTextBaseline] - points
        }
    }
}

private extension View {
    func baselineNudgeDown(_ points: CGFloat) -> some View {
        modifier(BaselineNudgeDown(points: points))
    }
}

