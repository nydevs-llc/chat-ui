//
//  SonataUIList.swift
//  Chat
//
//  Created by Bohdan Yankivskyi on 04.11.2025.
//

import SwiftUI

public extension Notification.Name {
    static let onScrollToBottom = Notification.Name("onScrollToBottom")
    static let onScrollToMessage = Notification.Name("onScrollToMessage")
    static let audioPlaybackStarted = Notification.Name("audioPlaybackStarted")
    static let recordingStarted = Notification.Name("recordingStarted")
    static let recordingStopped = Notification.Name("recordingStopped")
    static let uploadStarted = Notification.Name("uploadStarted")
    static let uploadFinished = Notification.Name("uploadFinished")
    static let startSharing = Notification.Name("startSharing")
    static let stopSharing = Notification.Name("stopSharing")
}

struct SonataUIList<MessageContent: View, InputView: View>: UIViewRepresentable {

    typealias MessageBuilderClosure =
        ChatView<MessageContent, InputView, DefaultMessageMenuAction>.MessageBuilderClosure

    @Environment(\.chatTheme) var theme

    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var inputViewModel: InputViewModel

    @Binding var isScrolledToBottom: Bool
    @Binding var shouldScrollToTop: () -> ()
    @Binding var tableContentHeight: CGFloat

    var messageBuilder: MessageBuilderClosure?
    var mainHeaderBuilder: (() -> AnyView)?
    var headerBuilder: ((Date) -> AnyView)?
    var inputView: InputView

    let type: ChatType
    let showDateHeaders: Bool
    let isScrollEnabled: Bool
    let avatarSize: CGFloat
    let showMessageMenuOnLongPress: Bool
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let tapDocumentClosure: ChatView.TapDocumentClosure?
    let paginationHandler: PaginationHandler?
    let messageStyler: (String) -> AttributedString
    let showMessageTimeView: Bool
    let messageFont: UIFont
    let sections: [MessagesSection]
    let ids: [String]
    let messageUseMarkdown: Bool
    let showAvatars: Bool
    let groupUsers: [User]
    var readTracker: MessageReadTracker?
    var scrollToMessageOnAppear: String?
    /// Отступ под плавающую панель ввода (`ChatView.floatingInputView`). У перевёрнутой
    /// ленты переписки визуальный низ — это `contentInset.top`.
    var bottomContentInset: CGFloat = 0
    /// Тап по чипу реакции под пузырём (эмоджи чипа); `nil` — реакции выключены.
    var reactionTap: ((Message, String) -> Void)?
    /// Рендер стикеров/больших эмодзи; кладётся в окружение каждой ячейки.
    var stickerRendering: ChatStickerRendering?
    /// Рендер кружков; кладётся в окружение каждой ячейки.
    var videoNoteRendering: ChatVideoNoteRendering?
    /// Подвал под сообщением; кладётся в окружение каждой ячейки.
    var messageFooterBuilder: MessageFooterBuilder?

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UIListLayout.makeLayout(
            chatType: type,
            showDateHeaders: showDateHeaders
        )

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.showsVerticalScrollIndicator = false
        cv.isScrollEnabled = isScrollEnabled
        cv.contentInsetAdjustmentBehavior = .never

        cv.delaysContentTouches = false
        cv.canCancelContentTouches = true
        
        if type == .conversation {
            cv.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        cv.register(SonataMessageCell.self, forCellWithReuseIdentifier: "cell")

        cv.register(UIListLayout.HeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: UIListLayout.HeaderView.reuseID)
        cv.register(UIListLayout.HeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                    withReuseIdentifier: UIListLayout.HeaderView.reuseID)

        cv.delegate = context.coordinator
        context.coordinator.attach(to: cv)

        // Токены держит координатор и снимает в `deinit`: замыкание с сильным
        // `context` раньше навсегда оставляло в памяти координатор ленты (и с ним
        // `ChatViewModel`, плеер голосовых и все сообщения) после каждого закрытия чата.
        let coordinator = context.coordinator
        coordinator.notificationTokens.append(
            NotificationCenter.default.addObserver(forName: .onScrollToBottom, object: nil, queue: .main) { [weak coordinator] _ in
                coordinator?.scrollToBottom(animated: true)
            }
        )
        coordinator.notificationTokens.append(
            NotificationCenter.default.addObserver(forName: .onScrollToMessage, object: nil, queue: .main) { [weak coordinator] notification in
                if let messageId = notification.object as? String {
                    coordinator?.scrollToMessage(messageId: messageId, animated: true)
                }
            }
        )

        DispatchQueue.main.async {
            shouldScrollToTop = { [weak cv] in
                guard let cv else { return }
                let offset = CGPoint(x: 0, y: max(-cv.adjustedContentInset.top, 0))
                cv.setContentOffset(offset, animated: false)
            }
        }

        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        cv.isScrollEnabled = isScrollEnabled
        // Отступ меняется вместе с панелью ввода и клавиатурой. Внутри анимации
        // клавиатуры (UIKit-блок, `inheritedAnimationDuration > 0`) хватает
        // простого присваивания. Всё остальное — рост панели ввода, панель
        // стикеров — приходит сюда без анимации (высота панели едет через
        // preference, транзакция `withAnimation` до неё не доживает), и отступ
        // прыгал мгновенно, пока сама панель ехала: сообщения подлетали и
        // падали обратно (Лев 17.10, C2). Поэтому такие смены анимируем кривой
        // клавиатуры (UIKit curve 7) — той же, какой едет клавиатура.
        if context.coordinator.isAnimatingInsertion {
            // Въезд строки сам доведёт ленту до нового низа (цель читается каждый кадр).
            applyBottomInset(to: cv, keepPinned: false)
        } else if UIView.inheritedAnimationDuration == 0, cv.window != nil, needsBottomInsetChange(cv) {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, UIView.AnimationOptions(rawValue: 7 << 16)]
            ) {
                applyBottomInset(to: cv)
            }
        } else {
            applyBottomInset(to: cv)
        }
        // Координатор держит копию `outer` со времени создания — свежий обработчик
        // кладём отдельно, иначе ячейки звали бы замыкание из первого рендера.
        context.coordinator.reactionTap = reactionTap
        context.coordinator.stickerRendering = stickerRendering
        context.coordinator.videoNoteRendering = videoNoteRendering
        context.coordinator.messageFooterBuilder = messageFooterBuilder
        // Данные не изменились — списку нечего делать.
        //
        // `apply(sections:)` на каждой перерисовке SwiftUI гонял диффинг и мог
        // выдать `reconfigureItems` от совершенно посторонних причин. Каждая
        // такая переконфигурация пересобирает SwiftUI-дерево ячейки, что дорого
        // само по себе и разрушительно для любого состояния внутри неё.
        if context.coordinator.lastSections != sections {
            context.coordinator.apply(sections: sections)
        }

        if !isScrollEnabled {
            DispatchQueue.main.async {
                self.tableContentHeight = cv.collectionViewLayout.collectionViewContentSize.height
            }
        }
    }

    /// Меняет отступ, не сбивая позицию: если лента стояла у последнего сообщения,
    /// она там и остаётся (панель выросла — сообщения поднимаются вместе с ней).
    private func needsBottomInsetChange(_ cv: UICollectionView) -> Bool {
        let current = type == .conversation ? cv.contentInset.top : cv.contentInset.bottom
        return abs(current - bottomContentInset) > 0.5
    }

    private func applyBottomInset(to cv: UICollectionView, keepPinned: Bool = true) {
        let flipped = type == .conversation
        let current = flipped ? cv.contentInset.top : cv.contentInset.bottom
        guard abs(current - bottomContentInset) > 0.5 else { return }

        if flipped {
            let wasAtBottom = keepPinned && cv.contentOffset.y <= -current + 1
            cv.contentInset.top = bottomContentInset
            cv.verticalScrollIndicatorInsets.top = bottomContentInset
            if wasAtBottom {
                cv.contentOffset.y = -bottomContentInset
            }
        } else {
            cv.contentInset.bottom = bottomContentInset
            cv.verticalScrollIndicatorInsets.bottom = bottomContentInset
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            outer: self,
            mainHeaderBuilder: mainHeaderBuilder,
            headerBuilder: headerBuilder,
            showDateHeaders: showDateHeaders,
            readTracker: readTracker,
            scrollToMessageOnAppear: scrollToMessageOnAppear
        )
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {

        struct SectionID: Hashable { let raw: Int }
        struct ItemID: Hashable { let raw: String }

        private weak var collectionView: UICollectionView?

        /// Один плеер голосовых на весь список.
        ///
        /// Живёт в координаторе, а не в строке, ровно потому, что координатор
        /// `UIViewRepresentable` переживает и `updateUIView`, и
        /// `reconfigureItems`, и переиспользование ячеек. Плеер в
        /// `@StateObject` внутри `UIHostingConfiguration` этого не переживал:
        /// присваивание `contentConfiguration` строит новое SwiftUI-дерево, и
        /// состояние воспроизведения создавалось заново пустым, пока старый
        /// плеер доигрывал запись. Играл один объект, рисовал другой.
        ///
        /// Одного плеера достаточно и по смыслу: в переписке одновременно
        /// звучит ровно одна запись — прежде это обеспечивалось рассылкой
        /// `.audioPlaybackStarted`, которая глушила все прочие экземпляры.
        let voicePlayer = RecordingPlayer()

        private var dataSource: UICollectionViewDiffableDataSource<SectionID, ItemID>!
        private let swipeToReply = SwipeToReplyController()
        /// «Вдавливание» пузыря при долгом нажатии (`MessagePress`).
        let pressTracker = MessagePressTracker()
        private var pressCommit: DispatchWorkItem?
        private var pressStartPoint: CGPoint = .zero
        private var pressedRow: MessageRow?
        private let keyboardDismiss = KeyboardDismissController()

        private let outer: SonataUIList
        private let mainHeaderBuilder: (() -> AnyView)?
        private let headerBuilder: ((Date) -> AnyView)?
        private let showDateHeaders: Bool
        private var readTracker: MessageReadTracker?
        private let scrollToMessageOnAppear: String?

        private var sectionIndexByID: [SectionID: Int] = [:]
        private var rowIndexByItemID: [ItemID: (s: Int, r: Int)] = [:]
        var lastSections: [MessagesSection] = []
        private var paginationTargetItemID: ItemID?
        private var hasPerformedInitialScroll = false

        var reactionTap: ((Message, String) -> Void)?
        var stickerRendering: ChatStickerRendering?
        var videoNoteRendering: ChatVideoNoteRendering?
        private var voicePlayRequestToken: NSObjectProtocol?
        /// Подписки `makeUIView` (`.onScrollToBottom`, `.onScrollToMessage`).
        var notificationTokens: [NSObjectProtocol] = []
        var messageFooterBuilder: MessageFooterBuilder?

        private var invertT: CGAffineTransform {
            outer.type == .conversation ? CGAffineTransform(scaleX: 1, y: -1) : .identity
        }

        init(
            outer: SonataUIList,
            mainHeaderBuilder: (() -> AnyView)?,
            headerBuilder: ((Date) -> AnyView)?,
            showDateHeaders: Bool,
            readTracker: MessageReadTracker?,
            scrollToMessageOnAppear: String?
        ) {
            self.outer = outer
            self.mainHeaderBuilder = mainHeaderBuilder
            self.headerBuilder = headerBuilder
            self.showDateHeaders = showDateHeaders
            self.readTracker = readTracker
            self.scrollToMessageOnAppear = scrollToMessageOnAppear
            super.init()
            // Последовательное воспроизведение (кружки → голосовое): приложение
            // просит общий плеер ленты сыграть запись.
            voicePlayRequestToken = NotificationCenter.default.addObserver(
                forName: .chatVoicePlayRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self, let recording = notification.object as? Recording else { return }
                // Живых лент может быть несколько (чат поверх чата, стек навигации):
                // играет только та, где есть это сообщение.
                if let messageId = notification.userInfo?["messageId"] as? String,
                   !self.lastSections.contains(where: { $0.rows.contains { $0.message.id == messageId } }) {
                    return
                }
                self.voicePlayer.startPlaying(recording)
            }
        }

        deinit {
            if let voicePlayRequestToken {
                NotificationCenter.default.removeObserver(voicePlayRequestToken)
            }
            notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func attach(to cv: UICollectionView) {
            self.collectionView = cv
            configureDataSource(for: cv)
            configureLongPress(on: cv)
            configureSwipeToReply(on: cv)
            keyboardDismiss.attach(to: cv)
//            cv.prefetchDataSource = self
        }

        private func configureDataSource(for cv: UICollectionView) {
            dataSource = UICollectionViewDiffableDataSource<SectionID, ItemID>(
                collectionView: cv
            ) { [weak self] collectionView, indexPath, itemID in
                guard let self else { return UICollectionViewCell() }
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)

                guard let (s, r) = self.rowIndexByItemID[itemID] else { return cell }
                let row = self.lastSections[s].rows[r]

                let messageView = ChatMessageView(
                    viewModel: self.outer.viewModel,
                    messageBuilder: self.outer.messageBuilder,
                    row: row,
                    chatType: self.outer.type,
                    avatarSize: self.outer.avatarSize,
                    tapAvatarClosure: self.outer.tapAvatarClosure,
                    messageUseMarkdown: self.outer.messageUseMarkdown,
                    isDisplayingMessageMenu: false,
                    showMessageTimeView: self.outer.showMessageTimeView,
                    showAvatar: self.outer.showAvatars,
                    messageFont: self.outer.messageFont,
                    tapDocumentClosure: self.outer.tapDocumentClosure,
                    groupUsers: self.outer.groupUsers
                )
                .background(MessageMenuPreferenceViewSetter(id: row.id))

                // Плеер отдаём ВНУТРИ замыкания: содержимое
                // `UIHostingConfiguration` — новый корень SwiftUI-дерева, и
                // окружение списка оно не наследует.
                let hostedView = MessagePressHost(
                    tracker: self.pressTracker,
                    id: row.id,
                    content: messageView
                        .sharedVoicePlayer(self.voicePlayer)
                        .environment(\.messageReactionTap, self.reactionTap)
                        .environment(\.chatStickerRendering, self.stickerRendering)
                        .environment(\.chatVideoNoteRendering, self.videoNoteRendering)
                        .environment(\.chatMessageFooterBuilder, self.messageFooterBuilder)
                )

                if #available(iOS 16.0, *) {
                    cell.contentConfiguration = UIHostingConfiguration { hostedView }
                        .margins(.all, 0)
                } else {
                    cell.contentConfiguration = UIHostingConfigurationBackport { hostedView }
                }

                cell.contentView.transform = self.invertT
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .clear
                cell.isUserInteractionEnabled = true
                return cell
            }

            dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
                guard let self, self.showDateHeaders else { return nil }

                let expectedKind: String = (self.outer.type == .conversation)
                    ? UICollectionView.elementKindSectionFooter
                    : UICollectionView.elementKindSectionHeader
                guard kind == expectedKind else { return nil }

                let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: UIListLayout.HeaderView.reuseID,
                    for: indexPath
                ) as! UIListLayout.HeaderView

                let section = self.lastSections[indexPath.section]
                header.host({
                    if let hb = self.headerBuilder {
                        return AnyView(hb(section.date))
                    } else {
                        return AnyView(
                            Text(section.formattedDate)
                                .font(.system(size: 11))
                                .padding(.top, 30)
                                .padding(.bottom, 8)
                                .foregroundColor(.gray)
                        )
                    }
                }, flipped: self.outer.type == .conversation)

                header.backgroundColor = .clear
                return header
            }
        }

        func apply(sections newSections: [MessagesSection]) {
            guard let cv = collectionView else { return }

            var snapshot = NSDiffableDataSourceSnapshot<SectionID, ItemID>()
            sectionIndexByID.removeAll()
            rowIndexByItemID.removeAll()

            for (sIdx, sec) in newSections.enumerated() {
                let secID = SectionID(raw: sec.id)
                snapshot.appendSections([secID])
                sectionIndexByID[secID] = sIdx

                let itemIDs = sec.rows.map { ItemID(raw: $0.id) }
                for (rIdx, itemID) in itemIDs.enumerated() {
                    rowIndexByItemID[itemID] = (sIdx, rIdx)
                }
                snapshot.appendItems(itemIDs, toSection: secID)
            }

            func flatByID(_ sections: [MessagesSection]) -> [String: MessageRow] {
                var dict: [String: MessageRow] = [:]
                for sec in sections { for row in sec.rows { dict[row.id] = row } }
                return dict
            }
            let oldByID = flatByID(lastSections)
            let newByID = flatByID(newSections)

            var changed: [ItemID] = []
            var textEdited: [ItemID] = []

            for (id, newRow) in newByID {
                if let oldRow = oldByID[id] {
                    if oldRow.message.text != newRow.message.text {
                        textEdited.append(ItemID(raw: id))
                    }

                    let deletedChanged = (oldRow.message.isDeleted != newRow.message.isDeleted)
                    let statusChanged = (oldRow.message.status != newRow.message.status)
                    
                    if deletedChanged || statusChanged || oldRow != newRow {
                        changed.append(ItemID(raw: id))
                    }
                }
            }

            lastSections = newSections

            if outer.type == .conversation,
               let lastSection = lastSections.last,
               let lastRow = lastSection.rows.last {
                paginationTargetItemID = ItemID(raw: lastRow.id)
            } else {
                paginationTargetItemID = nil
            }

            if !textEdited.isEmpty {
                snapshot.reloadItems(textEdited)
            }

            if !changed.isEmpty {
                let textSet = Set(textEdited)
                let onlyReconfigure = changed.filter { !textSet.contains($0) }
                if !onlyReconfigure.isEmpty {
                    snapshot.reconfigureItems(onlyReconfigure)
                }
            }

            // Вставка как в Telegram (Лев 17.10, A13 «скачет оффсет»): раньше diffable
            // анимировал вставку фейдом со строкой ОЦЕНОЧНОЙ высоты (44 pt), а
            // параллельно шёл `scrollToBottom(animated:)` своей кривой — строка
            // появлялась, затем самоподгонялась до настоящей высоты, и вся колонка
            // прыгала. Теперь снапшот применяется без анимации, раскладка считается
            // сразу (высоты финальные), и позиция ленты корректируется по якорю:
            // - у низа — колонка вместе с новой строкой въезжает снизу одной
            //   пружиной `ChatMotion.listDuration` (A2);
            // - в истории — видимый текст остаётся на месте (A3).
            let anchor = visibleAnchor()
            let isAnimating = offsetAnimator.isRunning
            let wasPinned = isAtBottom() || isAnimating
            let previousIDs = Set(oldByID.keys)
            dataSource.apply(snapshot, animatingDifferences: false) {
                // Perform initial scroll to unread message after layout completes
                if !self.hasPerformedInitialScroll, let messageId = self.scrollToMessageOnAppear {
                    self.hasPerformedInitialScroll = true
                    // Small delay to ensure all animations and layout updates are complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.scrollToMessage(messageId: messageId, animated: false)
                    }
                }
            }
            guard let anchor, outer.type == .conversation else {
                if wasPinned { scrollToBottom(animated: false) }
                return
            }
            cv.layoutIfNeeded()
            guard let path = dataSource.indexPath(for: anchor.id),
                  let frame = cv.layoutAttributesForItem(at: path)?.frame else {
                if wasPinned { scrollToBottom(animated: false) }
                return
            }
            let shift = frame.minY - anchor.minY
            if wasPinned {
                if shift > 0.5 {
                    // Колонка остаётся, где была, и одной пружиной уезжает вверх
                    // (вставка посреди идущей анимации продолжает её с текущего места).
                    cv.contentOffset.y += shift
                    fadeInInsertedCells(in: cv, previousIDs: previousIDs)
                    offsetAnimator.animate(cv) { [weak cv] in -(cv?.adjustedContentInset.top ?? 0) }
                } else if !isAnimating {
                    cv.contentOffset.y = -cv.adjustedContentInset.top
                }
            } else if abs(shift) > 0.5 {
                cv.contentOffset.y += shift
            }
        }

        /// Идёт въезд вставленной строки: лента считается прижатой к низу.
        var isAnimatingInsertion: Bool { offsetAnimator.isRunning }

        /// Аниматор смещения ленты (вставка у низа).
        private let offsetAnimator = ListOffsetAnimator()

        /// Видимая строка, по которой держится позиция ленты при обновлении:
        /// ближайшая к визуальному низу (в перевёрнутой ленте — с меньшим `minY`).
        private func visibleAnchor() -> (id: ItemID, minY: CGFloat)? {
            guard let cv = collectionView else { return nil }
            let visible = cv.indexPathsForVisibleItems.compactMap { path -> (ItemID, CGFloat)? in
                guard let id = dataSource.itemIdentifier(for: path),
                      let frame = cv.layoutAttributesForItem(at: path)?.frame else { return nil }
                return (id, frame.minY)
            }
            return visible.min { $0.1 < $1.1 }.map { (id: $0.0, minY: $0.1) }
        }

        /// Новые строки проявляются за 0.2 с, пока колонка въезжает.
        private func fadeInInsertedCells(in cv: UICollectionView, previousIDs: Set<String>) {
            for path in cv.indexPathsForVisibleItems {
                guard let id = dataSource.itemIdentifier(for: path),
                      !previousIDs.contains(id.raw),
                      let cell = cv.cellForItem(at: path) else { continue }
                cell.contentView.alpha = 0
                UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                    cell.contentView.alpha = 1
                }
            }
        }

        /// Свайп влево — ответ (`SwipeToReplyController`). Та же доступность, что у
        /// пункта «Ответить» меню: не в залоченном чате, не у удалённых/служебных.
        private func configureSwipeToReply(on cv: UICollectionView) {
            swipeToReply.targetAt = { [weak self] indexPath in
                guard let self,
                      self.outer.showMessageMenuOnLongPress,
                      self.outer.viewModel.messageMenuRow == nil,
                      let itemID = self.dataSource.itemIdentifier(for: indexPath),
                      let coords = self.rowIndexByItemID[itemID] else { return nil }
                let message = self.lastSections[coords.s].rows[coords.r].message
                guard !message.isDeleted, message.type != .status, message.type != .call else { return nil }
                if let note = message.videoNote, note.isRemoved, !message.user.isCurrentUser { return nil }
                let viewModel = self.outer.viewModel
                return SwipeToReplyController.Target(isOutgoing: message.user.isCurrentUser) {
                    viewModel.messageMenuActionInternal(message: message, action: .reply)
                }
            }
            swipeToReply.attach(to: cv)
        }

        /// Долгое нажатие как в Telegram (`MESSAGE_ANIMATIONS_SPEC.md`, A19): через
        /// 0.12 с пузырь 0.2 с «вдавливается», на конце — вибрация и меню, которое
        /// стартует со сжатого пузыря. Раньше было 0.35 с покоя и сразу меню (Лев 17.10,
        /// A15 «нет прожатия»).
        private func configureLongPress(on cv: UICollectionView) {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = MessagePress.delay
            lp.allowableMovement = MessagePress.cancelDistance
            lp.cancelsTouchesInView = false
            lp.delaysTouchesBegan = true
            lp.delegate = self
            cv.addGestureRecognizer(lp)
        }

        @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard let cv = collectionView else { return }
            switch gr.state {
            case .began:
                beginPress(at: gr.location(in: cv), in: cv)
            case .changed:
                // Палец поехал или пошёл скролл — это не нажатие на пузырь.
                let point = gr.location(in: cv)
                let moved = hypot(point.x - pressStartPoint.x, point.y - pressStartPoint.y)
                if pressCommit != nil, moved > MessagePress.cancelDistance || cv.isDragging {
                    cancelPress()
                }
            default:
                // Отпустили до меню — пузырь разжимается.
                if pressCommit != nil { cancelPress() }
            }
        }

        private func beginPress(at point: CGPoint, in cv: UICollectionView) {
            guard outer.showMessageMenuOnLongPress,
                  !cv.isDragging, !cv.isDecelerating,
                  cv.convert(point, to: nil).x > MessagePress.leftEdgeInset,
                  let indexPath = cv.indexPathForItem(at: point),
                  let itemID = dataSource.itemIdentifier(for: indexPath),
                  let coords = rowIndexByItemID[itemID]
            else { return }

            let row = lastSections[coords.s].rows[coords.r]
            let msg = row.message
            guard outer.viewModel.messageMenuRow == nil,
                  !msg.isDeleted, msg.type != .status, msg.type != .call else { return }

            pressStartPoint = point
            pressedRow = row
            pressTracker.press(row.id)
            let commit = DispatchWorkItem { [weak self] in self?.commitPress() }
            pressCommit = commit
            DispatchQueue.main.asyncAfter(deadline: .now() + MessagePress.duration, execute: commit)
        }

        private func commitPress() {
            pressCommit = nil
            guard let row = pressedRow, outer.viewModel.messageMenuRow == nil else {
                cancelPress()
                return
            }
            pressedRow = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
            // Скролл тем же пальцем после открытия меню не продолжается.
            if let pan = collectionView?.panGestureRecognizer {
                pan.isEnabled = false
                pan.isEnabled = true
            }
            outer.viewModel.messageMenuOpensFromPress = true
            outer.viewModel.messageMenuRow = row
            // Копия в меню встаёт поверх сжатого оригинала и разжимается той же
            // пружиной: оригинал под ней разжимается синхронно и не выглядывает.
            pressTracker.release(ContextMenuStyle.appearSpring.delay(0.1))
        }

        private func cancelPress() {
            pressCommit?.cancel()
            pressCommit = nil
            pressedRow = nil
            pressTracker.release()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // Палец главнее анимации вставки.
            offsetAnimator.stop()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let atBottom: Bool
            if outer.type == .conversation {
                // Кнопка «вниз» (A15 спеки анимаций, Telegram): появляется, когда до
                // низа ≥ 40 pt, прячется ближе 20 pt. Раньше порог был 0.5 pt — кнопка
                // мигала от любого сдвига, включая въезд новой строки и смену отступа
                // под панель ввода. Пока вставка везёт ленту к низу — лента «внизу».
                let distance = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                if offsetAnimator.isRunning {
                    atBottom = true
                } else if outer.isScrolledToBottom {
                    atBottom = distance < ScrollToBottomButtonThreshold.show
                } else {
                    atBottom = distance <= ScrollToBottomButtonThreshold.hide
                }
            } else {
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                atBottom = scrollView.contentOffset.y >= maxY - 0.5
            }

            if outer.isScrolledToBottom != atBottom {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.outer.isScrolledToBottom != atBottom {
                        self.outer.isScrolledToBottom = atBottom
                    }
                }
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let cv = collectionView else { return }
            // Вставка уже везёт ленту к низу своей пружиной.
            if offsetAnimator.isRunning { return }
            if outer.type == .conversation {
                let y = -cv.adjustedContentInset.top
                cv.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
            } else {
                let maxY = max(0, cv.collectionViewLayout.collectionViewContentSize.height - cv.bounds.height + cv.adjustedContentInset.bottom)
                cv.setContentOffset(CGPoint(x: 0, y: maxY), animated: animated)
            }
        }

        func scrollToMessage(messageId: String, animated: Bool) {
            guard let cv = collectionView else { return }
            let itemID = ItemID(raw: messageId)

            guard let coords = rowIndexByItemID[itemID] else {
                print("[⚠️ Chat] Message not found for scroll: \(messageId)")
                return
            }

            let indexPath = IndexPath(item: coords.r, section: coords.s)

            // Verify the indexPath is valid before scrolling
            guard coords.s < lastSections.count,
                  coords.r < lastSections[coords.s].rows.count else {
                print("[⚠️ Chat] Invalid indexPath for message: \(messageId)")
                return
            }

            cv.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        }

        func isAtBottom() -> Bool {
            guard let cv = collectionView else { return false }
            if outer.type == .conversation {
                return cv.contentOffset.y <= -cv.adjustedContentInset.top + 0.5
            } else {
                let maxY = max(0, cv.contentSize.height - cv.bounds.height + cv.adjustedContentInset.bottom)
                return cv.contentOffset.y >= maxY - 0.5
            }
        }
        
        func collectionView(_ collectionView: UICollectionView,
                            willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  let coords = rowIndexByItemID[itemID] else { return }

            let row = lastSections[coords.s].rows[coords.r]

            // Pagination handling
            if outer.type == .conversation,
               let paginationHandler = outer.paginationHandler,
               let targetID = paginationTargetItemID,
               itemID == targetID {
                Task {
                    await paginationHandler.handleClosure(row.message)
                }
            }

            // Read tracking
            if let readTracker = readTracker, !row.message.user.isCurrentUser {
                readTracker.messageDidAppear(messageId: row.message.id, createdAt: row.message.createdAt)
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            didEndDisplaying cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            // Note: itemIdentifier may return nil for items that were removed
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  let coords = rowIndexByItemID[itemID],
                  coords.s < lastSections.count,
                  coords.r < lastSections[coords.s].rows.count else {
                return
            }

            let row = lastSections[coords.s].rows[coords.r]

            // Read tracking
            if let readTracker = readTracker {
                readTracker.messageDidDisappear(messageId: row.message.id)
            }
        }

        /// Нажатие идёт вместе со скроллом: начался скролл — нажатие отменяется
        /// (`handleLongPress`, `.changed`), а не блокирует ленту.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func collectionView(_ collectionView: UICollectionView,
                            prefetchItemsAt indexPaths: [IndexPath]) { }

        func collectionView(_ collectionView: UICollectionView,
                            cancelPrefetchingForItemsAt indexPaths: [IndexPath]) { }
    }
}

private enum UIListLayout {
    static func makeLayout(chatType: ChatType, showDateHeaders: Bool) -> UICollectionViewLayout {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 0
        config.scrollDirection = .vertical

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                  heightDimension: .estimated(44))
            )
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                  heightDimension: .estimated(44)),
                subitems: [item]
            )

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0

            guard showDateHeaders else { return section }

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(30)
            )

            if chatType == .conversation {
                let footer = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionFooter,
                    alignment: .bottom
                )
                section.boundarySupplementaryItems = [footer]
            } else {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                section.boundarySupplementaryItems = [header]
            }

            return section
        }, configuration: config)

        return layout
    }

    final class HeaderView: UICollectionReusableView {
        static let reuseID = "HeaderHost"

        /// Как у `SonataMessageCell`: заголовок даты не берёт вертикальный safe area,
        /// иначе его `UIHostingController` растёт на нижний инсет у края ленты.
        override var safeAreaInsets: UIEdgeInsets {
            super.safeAreaInsets.withoutVerticalInsets
        }
        private var hosting: UIHostingController<AnyView>?

        override func prepareForReuse() {
            super.prepareForReuse()
            hosting?.view.removeFromSuperview()
            hosting = nil
            transform = .identity
            layer.removeAllAnimations()
        }

        func host(_ builder: @escaping () -> AnyView, flipped: Bool) {
            hosting?.view.removeFromSuperview()
            hosting = nil

            let hc = UIHostingController(rootView: builder())
            hosting = hc

            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hc.view)

            NSLayoutConstraint.activate([
                hc.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                hc.view.topAnchor.constraint(equalTo: topAnchor),
                hc.view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            UIView.performWithoutAnimation {
                layer.removeAllAnimations()
                hc.view.transform = flipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
                layoutIfNeeded()
            }
        }
    }
}

/// Ячейка сообщения без вертикального safe area.
///
/// Содержимое ячейки — SwiftUI (`UIHostingConfiguration`), и её `contentView`
/// раскладывает его внутри safe area, прибавляя инсеты к высоте самоподгонки.
/// Лента тянется под плавающую панель ввода до самого низа экрана, поэтому у неё
/// есть нижний safe area (34 pt на iPhone с домашним индикатором). У перевёрнутой
/// ленты (`transform` y = −1) этот «низ» визуально наверху: строка у края получала
/// `safeAreaInsets.bottom` от 0 до 34 в зависимости от своей позиции, вырастала
/// на столько же, сдвигалась, инсет менялся — и так по кругу. Замер: все
/// 306 изменений высоты за прогон равны изменению инсета; лента качалась на 34 pt,
/// блокировала главный поток на 140–317 мс и (без округления высоты) падала в
/// `_UICollectionViewFeedbackLoopDebugger` («stuck in a recursive layout loop»).
///
/// Отступы от краёв экрана задаёт сама лента (`contentInset` под панель ввода),
/// а не ячейка, поэтому вертикальный safe area ячейке не нужен вовсе.
/// Горизонтальный оставлен: в альбомной ориентации пузыри не уходят под вырез.
final class SonataMessageCell: UICollectionViewCell {
    override var safeAreaInsets: UIEdgeInsets {
        super.safeAreaInsets.withoutVerticalInsets
    }
}

private extension UIEdgeInsets {
    var withoutVerticalInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
    }
}

/// Плавный сдвиг `contentOffset` ленты по кадрам дисплея.
///
/// Не `UIView.animate`: анимация `bounds` у `UICollectionView` раскладывает ячейки
/// сразу под конечную позицию, и строки, видимые только в середине пути, не
/// рисуются. Здесь смещение ставится каждый кадр — лента раскладывается как при
/// обычном скролле. Кривая — критически демпфированная пружина без перелёта
/// (Telegram: `listSpring`, 0.4 с; `MESSAGE_ANIMATIONS_SPEC.md` §1.1, A2).
@MainActor
final class ListOffsetAnimator: NSObject {
    /// Длительность вставки (Telegram `ListView`: 0.4 с).
    static let duration: CFTimeInterval = 0.4
    /// ω пружины: к концу `duration` пройдено 99% пути.
    private static let omega: Double = 16.6

    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var startY: CGFloat = 0
    /// Цель читается каждый кадр: отступ под панель ввода может смениться прямо
    /// во время въезда (поле очистилось после отправки), и лента обязана
    /// закончить точно у низа, а не у старого отступа.
    private var target: () -> CGFloat = { 0 }
    /// Время анимации копится по кадрам, а не берётся с часов: первый кадр после
    /// вставки тяжёлый (новая ячейка, первый кадр стикера), и по часам лента
    /// перескакивала бы сразу на треть пути. Шаг не больше 1/30 с — после
    /// подвисания движение продолжается с места, а не прыгает (замер: −58 pt за кадр).
    private var elapsed: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval?

    var isRunning: Bool { link != nil }

    func animate(_ scrollView: UIScrollView, to target: @escaping () -> CGFloat) {
        stop()
        guard !UIAccessibility.isReduceMotionEnabled else {
            scrollView.contentOffset.y = target()
            return
        }
        self.scrollView = scrollView
        startY = scrollView.contentOffset.y
        self.target = target
        elapsed = 0
        lastTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private static func curve(_ t: CFTimeInterval) -> Double {
        let x = omega * t
        return 1 - (1 + x) * exp(-x)
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else { stop(); return }
        if let lastTimestamp {
            elapsed += min(link.timestamp - lastTimestamp, 1.0 / 30.0)
        }
        lastTimestamp = link.timestamp
        let t = elapsed
        let targetY = target()
        if t >= Self.duration {
            scrollView.contentOffset.y = targetY
            stop()
            return
        }
        let progress = Self.curve(t) / Self.curve(Self.duration)
        scrollView.contentOffset.y = startY + (targetY - startY) * CGFloat(progress)
    }
}

/// Пороги кнопки «вниз» (Telegram: показ с 40 pt от низа; гистерезис, чтобы не мигала).
enum ScrollToBottomButtonThreshold {
    static let show: CGFloat = 40
    static let hide: CGFloat = 20
}
