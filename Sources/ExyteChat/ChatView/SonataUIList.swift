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

/// UIHostingController subclass that forces a clear background from the earliest lifecycle point,
/// preventing the default white `.systemBackground` flash on iOS 15.
private class ClearHostingController<Content: View>: UIHostingController<Content> {
    override func loadView() {
        super.loadView()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
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

        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")

        cv.register(UIListLayout.HeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: UIListLayout.HeaderView.reuseID)
        cv.register(UIListLayout.HeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                    withReuseIdentifier: UIListLayout.HeaderView.reuseID)

        cv.delegate = context.coordinator
        context.coordinator.attach(to: cv)

        NotificationCenter.default.addObserver(forName: .onScrollToBottom, object: nil, queue: .main) { _ in
            context.coordinator.scrollToBottom(animated: true)
        }

        NotificationCenter.default.addObserver(forName: .onScrollToMessage, object: nil, queue: .main) { notification in
            if let messageId = notification.object as? String {
                context.coordinator.scrollToMessage(messageId: messageId, animated: true)
            }
        }

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
        context.coordinator.apply(sections: sections)

        if !isScrollEnabled {
            DispatchQueue.main.async {
                self.tableContentHeight = cv.collectionViewLayout.collectionViewContentSize.height
            }
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
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {

        struct SectionID: Hashable { let raw: Int }
        struct ItemID: Hashable { let raw: String }

        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<SectionID, ItemID>!

        private let outer: SonataUIList
        private let mainHeaderBuilder: (() -> AnyView)?
        private let headerBuilder: ((Date) -> AnyView)?
        private let showDateHeaders: Bool
        private var readTracker: MessageReadTracker?
        private let scrollToMessageOnAppear: String?

        private var sectionIndexByID: [SectionID: Int] = [:]
        private var rowIndexByItemID: [ItemID: (s: Int, r: Int)] = [:]
        private var lastSections: [MessagesSection] = []
        private var paginationTargetItemID: ItemID?
        private var hasPerformedInitialScroll = false

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
        }

        func attach(to cv: UICollectionView) {
            self.collectionView = cv
            configureDataSource(for: cv)
            configureLongPress(on: cv)
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

                if #available(iOS 16.0, *) {
                    cell.contentConfiguration = UIHostingConfiguration { messageView }
                        .margins(.all, 0)
                } else {
                    cell.contentView.backgroundColor = .clear
                    let hc = ClearHostingController(rootView: messageView)
                    hc.view.translatesAutoresizingMaskIntoConstraints = false
                    // Add new view BEFORE removing old ones — no empty frame gap
                    cell.contentView.addSubview(hc.view)
                    NSLayoutConstraint.activate([
                        hc.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                        hc.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                        hc.view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                        hc.view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor)
                    ])
                    // Remove previous hosted views after the new one is in place
                    cell.contentView.subviews.filter { $0 !== hc.view }.forEach { $0.removeFromSuperview() }
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

            let stayPinned = isAtBottom()
            dataSource.apply(snapshot, animatingDifferences: stayPinned) {
                // Perform initial scroll to unread message after layout completes
                if !self.hasPerformedInitialScroll, let messageId = self.scrollToMessageOnAppear {
                    self.hasPerformedInitialScroll = true
                    // Small delay to ensure all animations and layout updates are complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.scrollToMessage(messageId: messageId, animated: false)
                    }
                }
            }
            if stayPinned { scrollToBottom(animated: true) }
        }

        private func configureLongPress(on cv: UICollectionView) {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.35
            lp.allowableMovement = 12
            lp.cancelsTouchesInView = false
            lp.delaysTouchesBegan = true
            cv.addGestureRecognizer(lp)
        }

        @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began,
                  let cv = collectionView,
                  outer.showMessageMenuOnLongPress
            else { return }

            if cv.isDragging || cv.isDecelerating { return }
            let point = gr.location(in: cv)
            guard let indexPath = cv.indexPathForItem(at: point),
                  let itemID = dataSource.itemIdentifier(for: indexPath),
                  let coords = rowIndexByItemID[itemID]
            else { return }

            let row = lastSections[coords.s].rows[coords.r]
            let msg = row.message
            guard outer.viewModel.messageMenuRow == nil,
                  !msg.isDeleted, msg.type != .status, msg.type != .call else { return }

            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred(intensity: 1.0)
            outer.viewModel.messageMenuRow = row
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let atBottom: Bool
            if outer.type == .conversation {
                atBottom = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
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
