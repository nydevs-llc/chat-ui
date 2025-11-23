//
//  ChatView.swift
//  Chat
//
//  Created by Alisa Mylnikova on 20.04.2022.
//

import SwiftUI
import FloatingButton
import ExyteMediaPicker

public typealias MediaPickerParameters = SelectionParamsHolder

public enum ChatType {
    case conversation // the latest message is at the bottom, new messages appear from the bottom
    case comments // the latest message is at the top, new messages appear from the top
}

public enum ReplyMode {
    case quote // when replying to message A, new message will appear as the newest message, quoting message A in its body
    case answer // when replying to message A, new message with appear direclty below message A as a separate cell without duplicating message A in its body
}

public struct ChatView<MessageContent: View, InputViewContent: View, MenuAction: MessageMenuAction>: View {
    
    /// To build a custom message view use the following parameters passed by this closure:
    /// - message containing user, attachments, etc.
    /// - position of message in its continuous group of messages from the same user
    /// - position of message in the section of messages from that day
    /// - position of message in its continuous group of comments (only works for .answer ReplyMode, nil for .quote mode)
    /// - closure to show message context menu
    /// - closure to pass user interaction, .reply for example
    /// - pass attachment to this closure to use ChatView's fullscreen media viewer
    public typealias MessageBuilderClosure = ((
        _ message: Message,
        _ positionInGroup: PositionInUserGroup,
        _ positionInMessagesSection: PositionInMessagesSection,
        _ positionInCommentsGroup: CommentsPosition?,
        _ showContextMenuClosure: @escaping () -> Void,
        _ messageActionClosure: @escaping (Message, DefaultMessageMenuAction) -> Void,
        _ showAttachmentClosure: @escaping (Attachment) -> Void
    ) -> MessageContent)
    
    /// To build a custom input view use the following parameters passed by this closure:
    /// - binding to the text in input view
    /// - InputViewAttachments to store the attachments from external pickers
    /// - current input view state: .message for main input view mode and .signature for input view in media picker mode
    /// - closure to pass user interaction, .recordAudioTap for example
    /// - dismiss keyboard closure
    public typealias InputViewBuilderClosure = (
        _ text: Binding<String>,
        _ attachments: InputViewAttachments,
        _ inputViewState: InputViewState,
        _ inputViewStyle: InputViewStyle,
        _ inputViewActionClosure: @escaping (InputViewAction) -> Void,
        _ dismissKeyboardClosure: ()->()
    ) -> InputViewContent
    
    /// To define custom message menu actions declare an enum conforming to MessageMenuAction. The library will show your custom menu options on long tap on message. Once the action is selected the following callback will be called:
    /// - action selected by the user from the menu. NOTE: when declaring this variable, specify its type (your custom descendant of MessageMenuAction) explicitly
    /// - a closure taking a case of default implementation of MessageMenuAction which provides simple actions handlers; you call this closure passing the selected message and choosing one of the default actions if you need them; or you can write a custom implementation for all your actions, in that case just ignore this closure
    /// - message for which the menu is displayed
    /// When implementing your own MessageMenuActionClosure, write a switch statement passing through all the cases of your MessageMenuAction, inside each case write your own action handler, or call the default one. NOTE: not all default actions work out of the box - e.g. for .edit you'll still need to provide a closure to save the edited text on your BE. Please see CommentsExampleView in ChatExample project for MessageMenuActionClosure usage example.
    public typealias MessageMenuActionClosure = (
        _ selectedMenuAction: MenuAction,
        _ defaultActionClosure: @escaping (Message, DefaultMessageMenuAction) -> Void,
        _ message: Message
    ) -> Void

    /// User and MessageId
    public typealias TapAvatarClosure = (User, String) -> ()
    
    /// User and MessageId
    public typealias TapDocumentClosure = (User, String) -> ()
    
    /// User and MessageId
    public typealias DocumentSelectionClosure = ([URL]) -> ()

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.chatTheme) private var theme
    @Environment(\.mediaPickerTheme) private var pickerTheme

    // MARK: - Parameters

    let type: ChatType
    let showAvatars: Bool
    let sections: [MessagesSection]
    let ids: [String]
    let didSendMessage: (DraftMessage) -> Void
    var reactionDelegate: ReactionDelegate?
    let draft: String
    let didChangeDraft: (String) -> Void

    // MARK: - View builders

    /// provide custom message view builder
    var messageBuilder: MessageBuilderClosure? = nil

    /// provide custom input view builder
    var inputViewBuilder: InputViewBuilderClosure? = nil

    /// message menu customization: create enum complying to MessageMenuAction and pass a closure processing your enum cases
    var messageMenuAction: MessageMenuActionClosure?

    /// content to display in between the chat list view and the input view
    var betweenListAndInputViewBuilder: (()->AnyView)?

    /// a header for the whole chat, which will scroll together with all the messages and headers
    var mainHeaderBuilder: (()->AnyView)?

    /// date section header builder
    var headerBuilder: ((Date)->AnyView)?
    var localization: ChatLocalization = createLocalization()

    // MARK: - Customization

    var isListAboveInputView: Bool = true
    var showDateHeaders: Bool = true
    var isScrollEnabled: Bool = true
    var avatarSize: CGFloat = 32
    var messageStyler: (String) -> AttributedString = AttributedString.init
    var messageUseMarkdown: Bool = false
    var showMessageMenuOnLongPress: Bool = true
    var showNetworkConnectionProblem: Bool = false
    var messageMenuAnimationDuration: Double = 0.3
    var tapAvatarClosure: TapAvatarClosure?
    var tapDocumentClosure: TapDocumentClosure?
    var documentSelectionClosure: DocumentSelectionClosure?
    var mediaPickerSelectionParameters: MediaPickerParameters?
    var orientationHandler: MediaPickerOrientationHandler = {_ in}
    var chatTitle: String?
    var paginationHandler: PaginationHandler?
    var showMessageTimeView = true
    var messageFont = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))
    var availablelInput: AvailableInputType = .full
    var messageReadTracker: MessageReadTracker?

    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var inputViewModel = InputViewModel()
    @StateObject private var mentionsViewModel = MentionsSuggestionsViewModel()
    @StateObject private var globalFocusState = GlobalFocusState()
    @StateObject private var keyboardState = KeyboardState()

    @State private var isScrolledToBottom: Bool = true
    @State private var shouldScrollToTop: () -> () = {}

    @State private var isShowingMenu = false
    @State private var tableContentHeight: CGFloat = 0
    @State private var cellFrames = [String: CGRect]()
    @State private var inputViewSize = CGSize.zero

    @State private var showAttachmentSavedAlert: Bool = false
    @State private var isUploading: Bool = false
    @State private var retryCount = 0
    let groupUsers: [User]

    public init(
        messages: [Message],
        chatType: ChatType = .conversation,
        replyMode: ReplyMode = .quote,
        showAvatars: Bool = true,
        didSendMessage: @escaping (DraftMessage) -> Void,
        reactionDelegate: ReactionDelegate? = nil,
        messageBuilder: @escaping MessageBuilderClosure,
        inputViewBuilder: @escaping InputViewBuilderClosure,
        messageMenuAction: MessageMenuActionClosure?,
        draft: String = "",
        didChangeDraft: @escaping (String) -> Void,
        groupUsers: [User]
    ) {
        self.type = chatType
        self.didSendMessage = didSendMessage
        self.sections = ChatView.mapMessages(messages, chatType: chatType, replyMode: replyMode)
        self.ids = messages.map { $0.id }
        self.messageBuilder = messageBuilder
        self.inputViewBuilder = inputViewBuilder
        self.messageMenuAction = messageMenuAction
        self.showAvatars = showAvatars
        self.draft = draft
        self.didChangeDraft = didChangeDraft
        self.groupUsers = groupUsers
        self.reactionDelegate = reactionDelegate
    }

    public var body: some View {
        ZStack {
        mainView
                .background(content: {
                    if let backgroundImage = theme.images.conversation.background {
                        backgroundImage
                            .resizable()
                            .scaledToFill()
                    }
                })
                .background(theme.colors.mainBackground)
                .environmentObject(keyboardState)

            .fullScreenCover(isPresented: $viewModel.fullscreenAttachmentPresented) {
                let attachments = sections.flatMap { section in section.rows.flatMap { $0.message.attachments } }
                let index = attachments.firstIndex { $0.id == viewModel.fullscreenAttachmentItem?.id }

                GeometryReader { g in
                    FullscreenMediaPages(
                        viewModel: FullscreenMediaPagesViewModel(
                            attachments: attachments,
                            index: index ?? 0
                        ),
                        safeAreaInsets: g.safeAreaInsets,
                        onClose: { [weak viewModel] in
                            viewModel?.dismissAttachmentFullScreen()
                        },
                        onSave: { index in
                            let attachment = attachments[index]
                            // Save attachment to user's photo library
                            AttachmentSaver.saveToPhotoLibrary(attachment: attachment) { success in
                                if success {
                                    // Show success alert after small delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        showAttachmentSavedAlert = true
                                    }
                                } else {
                                    // Saving failed
                                    print("[❌ Save Failed] Could not save attachment.")
                                }
                            }
                        }
                    )
                    .ignoresSafeArea()
                }
            }
        
            .confirmationDialog("", isPresented: $inputViewModel.showAttachmentsSheet, titleVisibility: .hidden) {
                ForEach(AttachmentAction.allCases, id: \.self) { action in
                    Button(action.title) {
                        switch action {
                        case .gallery:
                            inputViewModel.mediaPickerMode = .photos
                            inputViewModel.showPicker = true
                        case .file:
                            inputViewModel.showFilePicker = true
                        case .location:
                            inputViewModel.showLocationPicker = true
                        }
                    }
                }
            }
        
            .fullScreenCover(isPresented: $inputViewModel.showLocationPicker) {
                LocationPickerView { selectedLocation in
                    inputViewModel.sendLocationMessage(selectedLocation)
                }
            }

            .fullScreenCover(isPresented: $inputViewModel.showPicker) {
                makeAttachmentsEditor()
            }
        
            .alert("Медіа-файл успішно збережено", isPresented: $showAttachmentSavedAlert) {
                Button("OK", role: .cancel) { }
            }
        
            .fileImporter(
                isPresented: $inputViewModel.showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onCompletion: { result in
                    switch result {
                    case .success(let urls):
                        documentSelectionClosure?(urls)
                    case .failure(_):
                        documentSelectionClosure?([])
                    }
                }
            )
        
            .onChange(of: inputViewModel.showAttachmentsSheet) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
        
            .onChange(of: inputViewModel.showLocationPicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }

            .onChange(of: inputViewModel.showPicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
        
            .onChange(of: inputViewModel.showFilePicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
            
            .onChange(of: isUploading) { _, uploading in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            
            .onChange(of: inputViewModel.text) { _, draft in
                didChangeDraft(draft)
            }
            
            if isUploading {
                ActivityIndicator(showBackground: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uploadStarted)) { _ in
            isUploading = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .uploadFinished)) { _ in
            isUploading = false
        }
    }
    
    @ViewBuilder
    func makeAttachmentsEditor() -> some View {
        AttachmentsEditor(
            inputViewModel: inputViewModel,
            inputViewBuilder: inputViewBuilder,
            chatTitle: chatTitle,
            messageUseMarkdown: messageUseMarkdown,
            orientationHandler: orientationHandler,
            mediaPickerSelectionParameters: mediaPickerSelectionParameters,
            availableInput: availablelInput
//            mediaPickerMode: $inputViewModel.mediaPickerMode
        )
        .environmentObject(globalFocusState)
    }

    var mainView: some View {
        VStack {

            if isListAboveInputView {
                listWithButton
                if let builder = betweenListAndInputViewBuilder {
                    builder()
                }
                inputView
            } else {
                inputView
                if let builder = betweenListAndInputViewBuilder {
                    builder()
                }
                listWithButton
            }
        }
        // Used to prevent ChatView movement during Emoji Keyboard invocation
        .ignoresSafeArea(isShowingMenu ? .keyboard : [])
    }

    @ViewBuilder
    var listWithButton: some View {
        switch type {
        case .conversation:
            ZStack(alignment: .bottomTrailing) {
                list

                if !isScrolledToBottom {
                    Button {
                        NotificationCenter.default.post(name: .onScrollToBottom, object: nil)
                    } label: {
                        theme.images.scrollToBottom
                            .frame(width: 40, height: 40)
                            .circleBackground(theme.colors.friendMessage)
                    }
                    .padding(8)
                }
            }

        case .comments:
            list
        }
    }

    @ViewBuilder
    var list: some View {
        SonataUIList(
//        UIList(
            viewModel: viewModel,
            inputViewModel: inputViewModel,
            isScrolledToBottom: $isScrolledToBottom,
            shouldScrollToTop: $shouldScrollToTop,
            tableContentHeight: $tableContentHeight,
            messageBuilder: messageBuilder,
            mainHeaderBuilder: mainHeaderBuilder,
            headerBuilder: headerBuilder,
            inputView: inputView,
            type: type,
            showDateHeaders: showDateHeaders,
            isScrollEnabled: isScrollEnabled,
            avatarSize: avatarSize,
            showMessageMenuOnLongPress: showMessageMenuOnLongPress,
            tapAvatarClosure: tapAvatarClosure,
            tapDocumentClosure: tapDocumentClosure,
            paginationHandler: paginationHandler,
            messageStyler: messageStyler,
//            shouldShowLinkPreview: shouldShowLinkPreview,
            showMessageTimeView: showMessageTimeView,
//            messageLinkPreviewLimit: messageLinkPreviewLimit,
            messageFont: messageFont,
            sections: sections,
            ids: ids,
            messageUseMarkdown: messageUseMarkdown,
            showAvatars: showAvatars,
            groupUsers: groupUsers,
            readTracker: messageReadTracker
//            listSwipeActions: listSwipeActions
        )
        .applyIf(!isScrollEnabled) {
            $0.frame(height: tableContentHeight)
        }
        .onStatusBarTap {
            shouldScrollToTop()
        }
        .transparentNonAnimatingFullScreenCover(item: $viewModel.messageMenuRow) {
            if let row = viewModel.messageMenuRow {
                messageMenu(row)
                    .onAppear(perform: showMessageMenu)
            }
            
        }
        .onPreferenceChange(MessageMenuPreferenceKey.self) { frames in
            DispatchQueue.main.async {
                self.cellFrames = frames
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                globalFocusState.focus = nil
            }
        )
        .onAppear {
            viewModel.didSendMessage = didSendMessage
            viewModel.inputViewModel = inputViewModel
            viewModel.globalFocusState = globalFocusState

            inputViewModel.didSendMessage = { value in
                Task { @MainActor in
                    didSendMessage(value)
                }
                if type == .conversation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .onScrollToBottom, object: nil)
                    }
                }
            }
            inputViewModel.text = draft
        }
    }

    var inputView: some View {
        Group {
            if let inputViewBuilder = inputViewBuilder {
                inputViewBuilder(
                    $inputViewModel.text,
                    inputViewModel.attachments,
                    inputViewModel.state,
                    .message,
                    inputViewModel.inputViewAction()
                ) {
                    globalFocusState.focus = nil
                }
            } else {
                InputView(
                    mentionsViewModel: preparedMentionsViewModel(),
                    viewModel: inputViewModel,
                    inputFieldId: viewModel.inputFieldId,
                    style: .message,
                    availableInput: availablelInput,
                    messageUseMarkdown: messageUseMarkdown
                )
            }
        }
        .sizeGetter($inputViewSize)
        .environmentObject(globalFocusState)
        .onAppear(perform: inputViewModel.onStart)
        .onDisappear(perform: inputViewModel.onStop)
    }

    func messageMenu(_ row: MessageRow) -> some View {
        let cellFrame = cellFrames[row.id] ?? .zero
        
        return MessageMenu(
            viewModel: viewModel,
            isShowingMenu: $isShowingMenu,
            message: row.message,
            isGroup: showAvatars, cellFrame: cellFrame,
            alignment: menuAlignment(row.message, chatType: type),
            positionInUserGroup: row.positionInUserGroup,
            leadingPadding: avatarSize + MessageView.horizontalAvatarPadding * 2,
            trailingPadding: MessageView.statusViewSize + MessageView.horizontalStatusPadding,
            font: messageFont,
            animationDuration: messageMenuAnimationDuration,
            onAction: menuActionClosure(row.message),
            reactionHandler: MessageMenu.ReactionConfig(
                delegate: reactionDelegate,
                didReact: reactionClosure(row.message)
            )
        ) {
            ChatMessageView(
                viewModel: viewModel,
                messageBuilder: messageBuilder,
                row: row, chatType: type,
                avatarSize: avatarSize,
                tapAvatarClosure: tapAvatarClosure,
                messageUseMarkdown: messageUseMarkdown,
                isDisplayingMessageMenu: true,
                showMessageTimeView: showMessageTimeView,
                showAvatar: showAvatars,
                messageFont: messageFont,
                tapDocumentClosure: tapDocumentClosure,
                groupUsers: groupUsers)
            .onTapGesture {
                hideMessageMenu()
            }
        }
    }
    
    /// Determines the message menu alignment based on ChatType and message sender.
    private func menuAlignment(_ message: Message, chatType: ChatType) -> MessageMenuAlignment {
        switch chatType {
        case .conversation:
            return message.user.isCurrentUser ? .right : .left
        case .comments:
            return .left
        }
    }
    
    /// Our default reactionCallback flow if the user supports Reactions by implementing the didReactToMessage closure
    private func reactionClosure(_ message: Message) -> (ReactionType?) -> () {
        return { reactionType in
            Task {
                // Run the callback on the main thread
                await MainActor.run {
                    // Hide the menu
                    hideMessageMenu()
                    // Send the draft reaction
                    guard let reactionDelegate, let reactionType else { return }
                    reactionDelegate.didReact(to: message, reaction: DraftReaction(messageID: message.id, type: reactionType))
                }
            }
        }
    }
    
    private static func createLocalization() -> ChatLocalization {
        return ChatLocalization(
            inputPlaceholder: String(localized: "Type a message..."),
            signatureText: String(localized: "Add signature..."),
            cancelButtonText: String(localized: "Cancel"),
            recentToggleText: String(localized: "Recents"),
            waitingForNetwork: String(localized: "Waiting for network"),
            recordingText: String(localized: "Recording..."),
            replyToText: String(localized: "Reply to")
        )
    }

    func menuActionClosure(_ message: Message) -> (MenuAction) -> () {
        if let messageMenuAction {
            return { action in
                hideMessageMenu()
                messageMenuAction(action, viewModel.messageMenuAction(), message)
            }
        } else if MenuAction.self == DefaultMessageMenuAction.self {
            return { action in
                hideMessageMenu()
                viewModel.messageMenuActionInternal(message: message, action: action as! DefaultMessageMenuAction)
            }
        }
        return { _ in }
    }
    
    func showMessageMenu() {
        isShowingMenu = true
    }
    
    func hideMessageMenu() {
        viewModel.messageMenuRow = nil
        viewModel.messageFrame = .zero
        isShowingMenu = false
    }
}

public extension ChatView {

    func betweenListAndInputViewBuilder<V: View>(_ builder: @escaping ()->V) -> ChatView {
        var view = self
        view.betweenListAndInputViewBuilder = {
            AnyView(builder())
        }
        return view
    }

    func mainHeaderBuilder<V: View>(_ builder: @escaping ()->V) -> ChatView {
        var view = self
        view.mainHeaderBuilder = {
            AnyView(builder())
        }
        return view
    }

    func headerBuilder<V: View>(_ builder: @escaping (Date)->V) -> ChatView {
        var view = self
        view.headerBuilder = { date in
            AnyView(builder(date))
        }
        return view
    }

    func isListAboveInputView(_ isAbove: Bool) -> ChatView {
        var view = self
        view.isListAboveInputView = isAbove
        return view
    }

    func showDateHeaders(_ showDateHeaders: Bool) -> ChatView {
        var view = self
        view.showDateHeaders = showDateHeaders
        return view
    }

    func isScrollEnabled(_ isScrollEnabled: Bool) -> ChatView {
        var view = self
        view.isScrollEnabled = isScrollEnabled
        return view
    }

    func showMessageMenuOnLongPress(_ show: Bool) -> ChatView {
        var view = self
        view.showMessageMenuOnLongPress = show
        return view
    }

    func showNetworkConnectionProblem(_ show: Bool) -> ChatView {
        var view = self
        view.showNetworkConnectionProblem = show
        return view
    }

    func assetsPickerLimit(assetsPickerLimit: Int) -> ChatView {
        var view = self
        view.mediaPickerSelectionParameters = MediaPickerParameters()
        view.mediaPickerSelectionParameters?.selectionLimit = assetsPickerLimit
        return view
    }

    func setMediaPickerSelectionParameters(_ params: MediaPickerParameters) -> ChatView {
        var view = self
        view.mediaPickerSelectionParameters = params
        return view
    }

    func orientationHandler(orientationHandler: @escaping MediaPickerOrientationHandler) -> ChatView {
        var view = self
        print("orientationHandler = \(orientationHandler)")
        view.orientationHandler = orientationHandler
        return view
    }

    /// when user scrolls up to `pageSize`-th meassage, call the handler function, so user can load more messages
    /// NOTE: doesn't work well with `isScrollEnabled` false
    func enableLoadMore(pageSize: Int, _ handler: @escaping ChatPaginationClosure) -> ChatView {
        var view = self
        view.paginationHandler = PaginationHandler(handleClosure: handler, pageSize: pageSize)
        return view
    }

    @available(*, deprecated)
    func chatNavigation(title: String, status: String? = nil, cover: URL? = nil) -> some View {
        var view = self
        view.chatTitle = title
        return view.modifier(ChatNavigationModifier(title: title, status: status, cover: cover))
    }

    // makes sense only for built-in message view

    func avatarSize(avatarSize: CGFloat) -> ChatView {
        var view = self
        view.avatarSize = avatarSize
        return view
    }

    func tapAvatarClosure(_ closure: @escaping TapAvatarClosure) -> ChatView {
        var view = self
        view.tapAvatarClosure = closure
        return view
    }
    
    func tapDocumentClosure(_ closure: @escaping TapDocumentClosure) -> ChatView {
        var view = self
        view.tapDocumentClosure = closure
        return view
    }
    
    func documentSelectionClosure(_ closure: @escaping DocumentSelectionClosure) -> ChatView {
        var view = self
        view.documentSelectionClosure = closure
        return view
    }

    func messageUseMarkdown(messageUseMarkdown: Bool) -> ChatView {
        var view = self
        view.messageUseMarkdown = messageUseMarkdown
        return view
    }

    func showMessageTimeView(_ isShow: Bool) -> ChatView {
        var view = self
        view.showMessageTimeView = isShow
        return view
    }

    func setMessageFont(_ font: UIFont) -> ChatView {
        var view = self
        view.messageFont = font
        return view
    }

    // makes sense only for built-in input view

    func setAvailableInput(_ type: AvailableInputType) -> ChatView {
        var view = self
        view.availablelInput = type
        return view
    }
    
    /// Sets the general duration of various message menu animations
    ///
    /// This value is more akin to 'how snappy' the message menu feels
    /// - Note: Good values are between 0.15 - 0.5 (defaults to 0.3)
    /// - Important: This value is clamped between 0.1 and 1.0
    func messageMenuAnimationDuration(_ duration:Double) -> ChatView {
        var view = self
        view.messageMenuAnimationDuration = max(0.1, min(1.0, duration))
        return view
    }
    
    /// Sets a ReactionDelegate on the ChatView for handling and configuring message reactions
    func messageReactionDelegate(_ configuration: ReactionDelegate) -> ChatView {
        var view = self
        view.reactionDelegate = configuration
        return view
    }
    
    /// Constructs, and applies, a ReactionDelegate for you based on the provided closures
    func onMessageReaction(
        didReactTo: @escaping (Message, DraftReaction) -> Void,
        canReactTo: ((Message) -> Bool)? = nil,
        availableReactionsFor: ((Message) -> [ReactionType]?)? = nil,
        allowEmojiSearchFor: ((Message) -> Bool)? = nil,
        shouldShowOverviewFor: ((Message) -> Bool)? = nil
    ) -> ChatView {
        var view = self
        view.reactionDelegate = DefaultReactionConfiguration(
            didReact: didReactTo,
            canReact: canReactTo,
            reactions: availableReactionsFor,
            allowEmojiSearch: allowEmojiSearchFor,
            shouldShowOverview: shouldShowOverviewFor
        )
        return view
    }

    /// Scrolls to a specific message by its ID
    /// - Parameter messageId: The ID of the message to scroll to
    /// - Parameter animated: Whether the scroll should be animated (default: true)
    func scrollToMessage(messageId: String, animated: Bool = true) {
        NotificationCenter.default.post(name: .onScrollToMessage, object: messageId)
    }

    /// Enables message read tracking with a callback
    /// - Parameters:
    ///   - debounceInterval: Time interval for debouncing updates (default: 1.0 second)
    ///   - minimumVisibilityDuration: Minimum time a message must be visible to be considered read (default: 0.5 seconds)
    ///   - onMessageRead: Callback called with the ID of the maximum visible message
    /// - Returns: Modified ChatView with read tracking enabled
    func enableMessageReadTracking(
        debounceInterval: TimeInterval = 1.0,
        minimumVisibilityDuration: TimeInterval = 0.5,
        onMessageRead: @escaping (String) -> Void
    ) -> ChatView {
        var view = self
        let tracker = MessageReadTracker(
            debounceInterval: debounceInterval,
            minimumVisibilityDuration: minimumVisibilityDuration
        )
        tracker.enable(callback: onMessageRead)
        view.messageReadTracker = tracker
        return view
    }
}

private extension ChatView {
    private func attemptToShowLoader() {
        guard !isUploading else { return }
        
        if isAnyAlertPresented() {
            if retryCount < 3 {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptToShowLoader()
                }
            }
        } else {
            isUploading = true
            retryCount = 0
        }
    }

    private func isAnyAlertPresented() -> Bool {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return false }
        
        return rootVC.presentedViewController != nil
    }
}

extension ChatView {
    private func preparedMentionsViewModel() -> MentionsSuggestionsViewModel {
        mentionsViewModel.setContext(users: groupUsers, isGroup: showAvatars)
        return mentionsViewModel
    }
}

import Foundation

public struct ChatLocalization: Hashable {
    public var inputPlaceholder: String
    public var signatureText: String
    public var cancelButtonText: String
    public var recentToggleText: String
    public var waitingForNetwork: String
    public var recordingText: String
    public var replyToText: String

    public init(inputPlaceholder: String, signatureText: String, cancelButtonText: String, recentToggleText: String, waitingForNetwork: String, recordingText: String, replyToText: String) {
        self.inputPlaceholder = inputPlaceholder
        self.signatureText = signatureText
        self.cancelButtonText = cancelButtonText
        self.recentToggleText = recentToggleText
        self.waitingForNetwork = waitingForNetwork
        self.recordingText = recordingText
        self.replyToText = replyToText
    }
}
