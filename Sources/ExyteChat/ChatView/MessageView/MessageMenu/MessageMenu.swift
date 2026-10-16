//
//  MessageMenu.swift
//  
//
//  Created by Alisa Mylnikova on 20.03.2023.
//

import SwiftUI

enum MessageMenuAlignment {
    case left
    case right
}

struct MessageMenu<MainButton: View, ActionEnum: MessageMenuAction>: View {
    
    @Environment(\.chatTheme) private var theme
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var keyboardState = KeyboardState()
    @StateObject var viewModel: ChatViewModel
    
    @Binding var isShowingMenu: Bool
    
    /// State to control inner message scrolling
    @State private var messageScrollable: Bool = false
    @State private var messageViewportHeight: CGFloat = .infinity
    
    /// Overall ChatView Frame
    let chatViewFrame: CGRect = UIScreen.main.bounds
    
    /// The max height for the menu
    /// - Note: menus that exceed this value will be placed in a ScrollView
//    let maxMenuHeight: CGFloat = 200
    let maxMenuHeight: CGFloat = 288 // make dynamic if needed
    /// The vertical spacing between the main three components in out VStack (ReactionSelection, Message and Menu)
    let verticalSpacing: CGFloat = 0
    
    /// The message whose menu we're presenting
    var message: Message
    /// The original message frame (the row / cell)
    ///  MUC message or not
    var isGroup: Bool
    var cellFrame: CGRect
    /// Leading / Trailing message alignment
    var alignment: MessageMenuAlignment
    /// The position in user group of the message
    var positionInUserGroup: PositionInUserGroup
    /// Leading padding (includes space for avatar)
    var leadingPadding: CGFloat
    /// Trailing padding
    var trailingPadding: CGFloat
    /// The font we should use to render our message menu button
    var font: UIFont? = nil
    /// The duration most of our animations take
    /// - Note: This value is more akin to 'how snappy' the menu feels. Good values are between 0.15 - 0.5
    var animationDuration: Double = 0.3
    /// The animation to use for displaying / dismissing this view
    var defaultTransition: AnyTransition = .scaleAndFade
    /// The menu button actions to be rendered
    var onAction: (ActionEnum) -> ()
    /// Реакции; `nil` — пилюли нет.
    var reactions: MessageReactionsConfiguration?
    /// Меню закончило закрываться — снять его с экрана.
    var onDismissed: () -> Void
    /// The main message, rendered as a button
    var mainButton: () -> MainButton

    /// The vertical offset necessary to ensure the message, and it's surrounding components,
    /// are visible on screen, and within the vertical safeAreaInsets.
    @State private var verticalOffset: CGFloat = 0
    /// The horizontal offset necessary to ensure the message, and it's surrounding components,
    /// are visible on screen, and within the horizontal safeAreaInsets.
    @State private var horizontalOffset: CGFloat = 0
    /// Used to store the previous `verticalOffset` when launching the emoji keyboard
    @State private var lastVerticalOffset: CGFloat = 0
    
    /// The current state that this view is in
    @State private var viewState: ViewState = .initial
    
    /// The style the message menu should be presented in
    /// Either a VStack or a ScrollView
    @State private var messageMenuStyle: MenuStyle = .vStack
    
    /// The style the menu should be presented in
    /// Either a VStack or a ScrollView
    @State private var menuStyle: MenuStyle = .vStack
    
    /// The Rendered MessageFrame Size
    /// - Note: These get populated during the `.prepare` viewState
    @State private var messageFrame: CGRect = .zero
    @State private var messageMenuFrame: CGRect = .zero
    @State private var reactionSelectionHeight: CGFloat = .zero
    @State private var reactionOverviewHeight: CGFloat = .zero
    @State private var reactionOverviewWidth: CGFloat = .zero
    @State private var menuHeight: CGFloat = .zero
    
    /// Controls whether or not the reaction selection view is rendered
    @State private var reactionSelectionIsVisible: Bool = true
    /// Controls whether or not the reaction overview is rendered
    @State private var reactionOverviewIsVisible: Bool = false
    /// Controls whether or not the menu view is rendered
    @State private var menuIsVisible: Bool = true
    
    /// Dynamic padding amounts
    @State private var reactionSelectionBottomPadding: CGFloat = 0
    @State private var messageTopPadding: CGFloat = 0
    /// Dynamic opacity vars
    @State private var messageMenuOpacity: CGFloat = 0.0
    @State private var backgroundOpacity: CGFloat = 0.0
    
    /// This flag is used to adjust the dismiss animation
    @State private var didReact: Bool = false
    /// Пилюля раскрыта в полную сетку эмоджи (меню действий в это время спрятано).
    @State private var reactionsExpanded: Bool = false
    /// Выбор отдаётся приложению сразу, а не после анимации закрытия: как у Telegram,
    /// реакция появляется под пузырём, пока меню ещё гаснет.
    private func handlePick(_ emoji: String, source: MessageReactionEvent.Source) {
        guard let reactions, !didReact else { return }
        didReact = true
        reactions.onEvent(message, .resolve(emoji, on: message, source: source))
        dismissSelf()
    }
    
    /// The max height for the entire message menu and surrounding views
    var maxEntireHeight: CGFloat {
        self.chatViewFrame.height
    }
    
    /// Unwraps and returns our optional `UIFont` as a `Font` or `nil`
    var getFont: Font? {
        if let font {
            return Font(font)
        } else {
            return nil
        }
    }
    
    var shouldShowReactionSelectionView: Bool {
        reactions?.canReact(message) ?? false
    }

    var shouldShowReactionOverviewView: Bool {
        reactions?.showsOverview(message) ?? false
    }

    var shouldAllowEmojiSearch: Bool {
        reactions?.allowsEmojiGrid(for: message) ?? false
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            
            // Reaction Overview Rectangle
            if reactionOverviewIsVisible, case .vStack = messageMenuStyle {
                ReactionOverview(viewModel: viewModel, message: message, width: reactionOverviewWidth, backgroundColor: theme.colors.mainBackground, inScrollView: false)
                    .frame(width: reactionOverviewWidth)
                    .maxHeightGetter($reactionOverviewHeight)
                    .offset(y: UIApplication.safeArea.top)
                    .transition(defaultTransition)
                    .opacity(messageMenuOpacity)
            }
            
            // Some views to help debug layout and animations
            //debugViews()
            
            // The message and menu view
            messageMenuView()
                .frameGetter($messageMenuFrame)
                .position(x: chatViewFrame.width / 2 + horizontalOffset, y: verticalOffset)
                .opacity(messageMenuOpacity)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
        .background(
            ContextMenuBackdrop()
            .edgesIgnoringSafeArea(.all)
            .opacity(backgroundOpacity)
            .onTapGesture {
                if viewState == .keyboard {
                    keyboardState.resignFirstResponder()
                    transitionViewState(to: .ready)
                } else {
                    dismissSelf()
                }
            }
        )
        .onAppear {
            transitionViewState(to: .prepare)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(animationDuration * 333))) {
                transitionViewState(to: .original)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(animationDuration * 666))) {
                transitionViewState(to: .ready)
            }
        }
        .onChange(of: keyboardState.keyboardFrame) { _ in
            if viewState == .ready, keyboardState.isShown {
                transitionViewState(to: .keyboard)
            }
        }
    }
    
    @MainActor
    private func transitionViewState(to vs: ViewState) {
        guard viewState != vs, viewState != .dismiss, vs != .initial else { return }
        let oldState = viewState
        viewState = vs
        switch viewState {
        case .initial:
            fatalError("Shouldn't be called")
            
        case .prepare:
            /// Ensure we set this to true
            isShowingMenu = true
            
            /// Set our view state variables
            reactionSelectionBottomPadding = positionInUserGroup == .middle || positionInUserGroup == .last ? 4 : 0
            reactionOverviewWidth = chatViewFrame.width - UIApplication.safeArea.leading - UIApplication.safeArea.trailing
            reactionOverviewIsVisible = shouldShowReactionOverviewView
            reactionSelectionIsVisible = shouldShowReactionSelectionView
            menuIsVisible = true
            verticalOffset = UIScreen.main.bounds.height * 2
            
        case .original:
            /// Our views were rendered transparently in the `.prepare` state allowing us to
            /// capture their preferred sizes (based on the devices dynamic text), so now we can configure our view

            /// If we have a detailed message frame stored in the viewModel use it, otherwise fall back to the cell's frame
            /// - Note: this optional message frame allows us to place the reaction at the correct spot on the message (top left / right corner)
            if viewModel.messageFrame == .zero {
                print("WARNING::ViewModel.MessageFrame not set")
                viewModel.messageFrame = cellFrame
            }
            
            /// If we're in landscape mode, adjust the `horizontalOffset` appropriately
            if UIScreen.main.bounds.width > UIScreen.main.bounds.height {
                switch alignment {
                case .left:
                    horizontalOffset = UIApplication.safeArea.leading
                case .right:
                    horizontalOffset = -UIApplication.safeArea.trailing
                }
            }
            messageFrame = .init(
                x: viewModel.messageFrame.origin.x + horizontalOffset,
                y: cellFrame.maxY - (viewModel.messageFrame.height),
                width: viewModel.messageFrame.width,
                height: viewModel.messageFrame.height
            )
            
            messageTopPadding = 4
            
            /// Calculate our vertical safe area insets
            let safeArea = UIApplication.safeArea.top + UIApplication.safeArea.bottom
            /// Calculate our ReactionOverview height
            let rOHeight:CGFloat = reactionOverviewIsVisible ? reactionOverviewHeight : 0
            /// We calculate the total height here, instead of using messageMenuFrame.height
            /// messageMenuHeight renders the menu buttons in a VStack by default, and we need to account for the clamping of the menu height
            let totalMenuHeight = calculateMessageMenuHeight(including: [.message, .reactionSelection]) + min(menuHeight, maxMenuHeight)
            /// Compare our total menu height with our free screen space to determine if we need to place it in a ScrollView or not
            if ( totalMenuHeight + rOHeight ) > maxEntireHeight - safeArea {
                /// We need to place our entire view in a ScrollView
                messageMenuStyle = .scrollView(height: maxEntireHeight - safeArea)
            } else if menuHeight > maxMenuHeight {
                /// We need to place our menu buttons in a ScrollView
                menuStyle = .scrollView(height: maxMenuHeight)
            }
            /// Update our view state variables
            /// Hide all of our views in preperation for our transition to `.ready`
            reactionSelectionIsVisible = false
            reactionOverviewIsVisible = false
            menuIsVisible = false
            recomputeMessageViewport()
            /// Calculate our vertical offset so our message lines up with the message from our TableView
            verticalOffset = calcVertOffset(previousState: oldState)
            /// Копия пузыря встаёт ровно поверх оригинала и показывается сразу, а фон
            /// начинает размываться только сейчас. Telegram держит пузырь чётким всё
            /// время: раньше фон стартовал ещё в `.prepare`, а копия проявлялась за
            /// ~0.4 с — сообщение на миг пропадало под блюром.
            messageMenuOpacity = 1.0
            withAnimation(ContextMenuStyle.backdropAnimation) {
                backgroundOpacity = 1.0
            }
            
        case .ready:
            withAnimation(ContextMenuStyle.appearSpring) {
                reactionSelectionIsVisible = shouldShowReactionSelectionView
                reactionOverviewIsVisible = shouldShowReactionOverviewView
                menuIsVisible = true
                recomputeMessageViewport()
                verticalOffset = calcVertOffset(previousState: oldState)
            }
            
        case .keyboard:
            withAnimation(ContextMenuStyle.appearSpring) {
                reactionSelectionIsVisible = true
                reactionOverviewIsVisible = false
                menuIsVisible = false
                recomputeMessageViewport()
                verticalOffset = calcVertOffset(previousState: oldState)
            }
            
        case .dismiss:
            withAnimation(ContextMenuStyle.dismissAnimation) {
                reactionsExpanded = false
                reactionSelectionIsVisible = didReact ? true : false
                reactionOverviewIsVisible = false
                menuIsVisible = false
                verticalOffset = calcVertOffset(previousState: oldState)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(animationDuration * 333))) {
                withAnimation(ContextMenuStyle.backdropAnimation) {
                    messageMenuOpacity = 0
                    backgroundOpacity = 0
                }
            }
        }
    }
    
    private func calcVertOffset(previousState: ViewState) -> CGFloat {
        switch viewState {
        case .initial, .prepare:
            return .greatestFiniteMagnitude
        case .original:
            return messageFrame.midY - (messageTopPadding / 2)
        case .ready:
            // Preserve smooth return from keyboard: keep previous Y
            if case .keyboard = previousState {
                // If entire stack is scrollable, re-evaluate style necessity after keyboard closed
                if case .scrollView(let height) = messageMenuStyle {
                    // Check whether we still need the outer scroll container
                    let rSelH: CGFloat = reactionSelectionIsVisible ? (reactionSelectionHeight + verticalSpacing + reactionSelectionBottomPadding) : 0
                    let rOvH:  CGFloat = reactionOverviewIsVisible ? reactionOverviewHeight : 0
                    let menuH: CGFloat = menuIsVisible ? (menuStyle.height(menuHeight) + verticalSpacing) : 0
                    let safe   = UIApplication.safeArea.top + UIApplication.safeArea.bottom
                    let contentHeight = (messageFrame.height + messageTopPadding) + rSelH + rOvH + menuH

                    if contentHeight <= (chatViewFrame.height - safe) {
                        // Collapse back to vStack if everything fits now
                        messageMenuStyle = .vStack
                    } else {
                        // Keep scrollView but ensure its height equals available viewport
                        let available = chatViewFrame.height - safe
                        messageMenuStyle = .scrollView(height: available)
                    }
                }
                return lastVerticalOffset
            }

            // If outer container is scrollable, center it between safe areas
            if case .scrollView(let height) = messageMenuStyle {
                return UIApplication.safeArea.top + (height / 2)
            }

            // Fixed bars (reactions/overview on top, actions on bottom).
            // Compute the vertical rails available for the message *viewport*.
            let rSelBar: CGFloat = reactionSelectionIsVisible
                ? (reactionSelectionHeight + verticalSpacing + reactionSelectionBottomPadding) : 0
            let rOvBar:  CGFloat = reactionOverviewIsVisible ? reactionOverviewHeight : 0
            let menuBar: CGFloat = menuIsVisible ? (menuStyle.height(menuHeight) + verticalSpacing) : 0

            let topRail    = UIApplication.safeArea.top + rOvBar + rSelBar
            let bottomRail = chatViewFrame.height - UIApplication.safeArea.bottom - menuBar
            let available  = max(0, bottomRail - topRail)

            if messageScrollable {
                // Center the *viewport* of the bubble, not its full natural height.
                let viewport = min(available, messageViewportHeight)
                return topRail + (viewport / 2)
            } else {
                // Legacy behavior for short bubbles: keep the bubble anchored near its natural spot,
                // but push it away from the top/bottom bars if it overlaps.
                var ty = messageFrame.midY - (messageTopPadding / 2)

                // Push down if the top of the bubble collides with the top rails
                if (messageFrame.minY) < (UIApplication.safeArea.top + rOvBar + rSelBar) {
                    let off = (UIApplication.safeArea.top + rOvBar + rSelBar) - (messageFrame.minY)
                    ty += off
                }
                // Push up if the bottom of the bubble collides with the bottom rails
                else if (messageFrame.maxY + menuBar) > (chatViewFrame.height - UIApplication.safeArea.bottom) {
                    let off = messageFrame.maxY + menuBar + UIApplication.safeArea.bottom - chatViewFrame.height
                    ty -= off
                }

                // Balance top/bottom chrome so the visual center is correct
                return ty + (menuBar / 2) - (rSelBar / 2)
            }
        case .keyboard:
            /// Store our vertical offset
            lastVerticalOffset = verticalOffset

            /// If the messageMenuStyle is a scrollView then we place it in the middle of the screen
            if case .scrollView(let height) = messageMenuStyle {
                /// Update our max height
                messageMenuStyle = .scrollView(height: height - keyboardState.keyboardFrame.height + UIApplication.safeArea.bottom)
                /// And our vertical offset
                return verticalOffset - (keyboardState.keyboardFrame.height / 2) + (UIApplication.safeArea.bottom / 2)
            } else {
                /// Check to make sure that we don't need a scroll view now that we have less realestate
                let contentHeight = calculateMessageMenuHeight(including: [.message, .reactionSelection])
                if contentHeight + UIApplication.safeArea.top > keyboardState.keyboardFrame.minY {
                    /// Our message is too large to fit in our available screen space
                    /// We *should* place the content in a ScrollView
                    /// But we don't due to needing to preserve the ReactionSelection's view state
                    /// Therefore we settle with clipping the bottom of the content behind the keyboard
                    /// Pin the view to the top of the screen
                    return UIApplication.safeArea.top + (contentHeight / 2)
                }
            }
            
            /// At this point our messageMenuFrame height includes the menu view so we need to subtract that
            let mHeight: CGFloat = calculateMessageMenuHeight(including: [.menu])

            /// Grab our current verticalOffset
            var ty: CGFloat = verticalOffset
            /// Keep the message stationary while we hide / remove the menu
            ty -= mHeight / 2
            /// Provide a bit of padding to lift the view off of the keyboard
            let bottomPadding = UIApplication.safeArea.bottom / 2
            if messageMenuFrame.maxY - mHeight + bottomPadding > keyboardState.keyboardFrame.minY {
                let off = messageMenuFrame.maxY - mHeight + bottomPadding - keyboardState.keyboardFrame.minY
                /// We need to move the message up so it doesn't get hidden by the keyboard
                ty -= off
            }
            return ty
            
        case .dismiss:
            if didReact {
                return messageFrame.midY - ((calculateMessageMenuHeight(including: [.reactionSelection])) / 2)
            } else {
                return messageFrame.midY - (messageTopPadding / 2)
            }
        }
    }
    
    enum MMViews {
        case message
        case menu
        case reactionSelection
    }
    
    /// Attempts to provide a single call site for gathering the height of our various views
    private func calculateMessageMenuHeight(including views: [MMViews]) -> CGFloat {
        var height: CGFloat = 0
        for view in Set(views) {
            switch view {
            case .message:
                height += messageFrame.height + messageTopPadding
            case .menu:
                height += menuStyle.height(menuHeight) + verticalSpacing
                if case .scrollView = menuStyle { height += 8 }
            case .reactionSelection:
                height += reactionSelectionHeight + verticalSpacing + reactionSelectionBottomPadding
            }
        }
        return height
    }
    
    @ViewBuilder
    func messageMenuView() -> some View {
        VStack(spacing: verticalSpacing) {
            if reactionOverviewIsVisible, case .scrollView = messageMenuStyle {
                ReactionOverview(viewModel: viewModel, message: message, width: reactionOverviewWidth, backgroundColor: theme.colors.friendMessage, inScrollView: true)
                    .frame(width: reactionOverviewWidth)
                    .maxHeightGetter($reactionOverviewHeight)
                    //.offset(y: safeAreaInsets.top)
                    .transition(defaultTransition)
                    .opacity(messageMenuOpacity)
            }
            
            if reactionSelectionIsVisible {
                reactionPillRow()
                    .padding(.bottom, reactionSelectionBottomPadding)
                    .transition(growTransition(from: pillTailAnchor))
                    .zIndex(2)
            }

            messageBubbleContainer()

            if menuIsVisible {
                menuView()
                    .transition(growTransition(from: menuGrowAnchor))
            }
        }
        .overflowContainer(messageMenuStyle, viewState: viewState, onTap: {
            if viewState == .keyboard {
                keyboardState.resignFirstResponder()
                transitionViewState(to: .ready)
            } else {
                dismissSelf()
            }
        })
    }
    
    // Replace current plain message rendering with a conditional scroll container
    @ViewBuilder
    private func messageBubbleContainer() -> some View {
        // Your message bubble (non-interactive clone)
        let bubble = mainButton()
            .frame(maxWidth: chatViewFrame.width - UIApplication.safeArea.leading - UIApplication.safeArea.trailing)
            .offset(x: (alignment == .right) ? UIApplication.safeArea.trailing : -UIApplication.safeArea.leading)
            .allowsHitTesting(false)

        if messageScrollable {
            ScrollView(.vertical, showsIndicators: true) {
                bubble
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
            .frame(height: messageViewportHeight)
            // Subtle edge fades to hint scrollability
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.0),
                        .init(color: .black,              location: 0.02),
                        .init(color: .black,              location: 0.98),
                        .init(color: .black.opacity(0.0), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .zIndex(1)
        } else {
            bubble
                .zIndex(1)
        }
    }
    
    private func recomputeMessageViewport() {
        let rSel = reactionSelectionIsVisible
            ? (reactionSelectionHeight + verticalSpacing + reactionSelectionBottomPadding) : 0
        let rOv  = reactionOverviewIsVisible ? reactionOverviewHeight : 0
        let menu = menuIsVisible ? (menuStyle.height(menuHeight) + verticalSpacing) : 0

        let chrome = UIApplication.safeArea.top + UIApplication.safeArea.bottom + rSel + rOv + menu
        let available = max(0, maxEntireHeight - chrome)
        let bubble = messageFrame.height + messageTopPadding

        messageScrollable = bubble > available
        messageViewportHeight = min(bubble, available)
    }

    // MARK: - Telegram-style layout

    private var isIncoming: Bool { alignment == .left }

    /// Фрейм пузыря на экране. Пока копия в меню не замерилась — фрейм ячейки.
    private var anchorFrame: CGRect {
        viewModel.messageFrame == .zero ? cellFrame : viewModel.messageFrame
    }

    /// Свои уже поставленные реакции идут первыми, чтобы их было легко снять (как в форке до этого).
    private var pillEmojis: [String] {
        let base = reactions?.quickReactions(for: message) ?? MessageReactionsConfiguration.telegramQuickReactions
        let own = message.reactions.filter { $0.user.isCurrentUser }.compactMap(\.emoji)
        var result = own.filter { !base.contains($0) }
        for emoji in base where !result.contains(emoji) { result.append(emoji) }
        return Array(result.prefix(ContextMenuStyle.maxVisibleEmojis))
    }

    private var pillLayout: ReactionPillLayout {
        ReactionPillLayout(
            anchor: anchorFrame,
            isIncoming: isIncoming,
            slotCount: pillEmojis.count + (shouldAllowEmojiSearch ? 1 : 0),
            screenWidth: chatViewFrame.width
        )
    }

    /// Пилюля вырастает из хвоста — точки над краем пузыря.
    private var pillTailAnchor: UnitPoint {
        let layout = pillLayout
        return UnitPoint(x: (layout.minX + layout.tailX) / chatViewFrame.width, y: 1)
    }

    /// Отступ меню от края экрана: Telegram ровняет его по краю пузыря со стороны отправителя.
    private var menuEdgeInset: CGFloat {
        let inset = isIncoming ? anchorFrame.minX : chatViewFrame.width - anchorFrame.maxX
        return max(ContextMenuStyle.actionsScreenInset, inset)
    }

    /// Меню вырастает из угла под пузырём, а не из своего центра.
    private var menuGrowAnchor: UnitPoint {
        let x = isIncoming ? menuEdgeInset : chatViewFrame.width - menuEdgeInset
        return UnitPoint(x: x / chatViewFrame.width, y: 0)
    }

    private func growTransition(from anchor: UnitPoint) -> AnyTransition {
        .scale(scale: 0.01, anchor: anchor).combined(with: .opacity)
    }

    @ViewBuilder
    private func reactionPillRow() -> some View {
        let layout = pillLayout
        ReactionPillView(
            emojis: pillEmojis,
            selectedEmojis: message.reactions.filter { $0.user.isCurrentUser }.compactMap(\.emoji),
            layout: layout,
            selectedColor: theme.colors.myMessage,
            allowsExpand: shouldAllowEmojiSearch,
            isExpanded: reactionsExpanded,
            expandedHeight: expandedPanelHeight,
            expandAccessibilityLabel: reactions?.expandAccessibilityLabel ?? "More reactions",
            collapseAccessibilityLabel: reactions?.collapseAccessibilityLabel ?? "Close",
            onExpandedChange: setReactionsExpanded,
            onPick: handlePick
        )
        // Строка держит высоту свёрнутой пилюли: раскрытая сетка растёт вниз поверх
        // пузыря (zIndex строки выше), а не расталкивает раскладку.
        .frame(height: ContextMenuStyle.pillHeight, alignment: .top)
        .padding(.leading, layout.minX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ContextMenuStyle.pillBubbleGap)
        .maxHeightGetter($reactionSelectionHeight)
    }

    /// Высота раскрытой сетки: Telegram держит её около половины экрана.
    private var expandedPanelHeight: CGFloat {
        min(380, chatViewFrame.height * 0.5)
    }

    private func setReactionsExpanded(_ expanded: Bool) {
        guard viewState == .ready, expanded != reactionsExpanded else { return }
        // Считаем ДО смены флагов: нужны текущие верх стека и высота меню.
        let expandedOffset = expandedVerticalOffset()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            reactionsExpanded = expanded
            menuIsVisible = !expanded
            reactionOverviewIsVisible = expanded ? false : shouldShowReactionOverviewView
            verticalOffset = expanded ? expandedOffset : calcVertOffset(previousState: .ready)
        }
    }

    /// Верх пилюли остаётся на месте; стек поднимается ровно настолько, чтобы раскрытая
    /// сетка влезла над нижней безопасной зоной. Меню прячется — стек становится ниже,
    /// а `.position` центрирует, поэтому центр пересчитывается от сохранённого верха.
    private func expandedVerticalOffset() -> CGFloat {
        let top = messageMenuFrame.minY
        let menuBar = menuIsVisible ? menuStyle.height(menuHeight) : 0
        let stackHeight = max(0, messageMenuFrame.height - menuBar)
        let bottomLimit = chatViewFrame.height - UIApplication.safeArea.bottom - 8
        let overflow = max(0, top + expandedPanelHeight - bottomLimit)
        let newTop = max(UIApplication.safeArea.top + 8, top - overflow)
        return newTop + stackHeight / 2
    }

    @ViewBuilder
    func menuView() -> some View {
        let actions = filteredMenuActions()
        let regular = actions.filter { $0.type() != .delete }
        let destructive = actions.filter { $0.type() == .delete }

        VStack(spacing: 0) {
            menuRows(regular)
            if !regular.isEmpty && !destructive.isEmpty {
                ContextMenuSeparator()
            }
            menuRows(destructive)
        }
        .padding(.vertical, ContextMenuStyle.actionsVerticalInset)
        .frame(minWidth: ContextMenuStyle.actionsMinWidth, maxWidth: ContextMenuStyle.actionsMaxWidth)
        .fixedSize(horizontal: true, vertical: false)
        .menuContainer(menuStyle)
        .clipShape(RoundedRectangle(cornerRadius: ContextMenuStyle.actionsCornerRadius, style: .continuous))
        .contextMenuSurface(RoundedRectangle(cornerRadius: ContextMenuStyle.actionsCornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: isIncoming ? .leading : .trailing)
        .padding(isIncoming ? .leading : .trailing, menuEdgeInset)
        .padding(.top, ContextMenuStyle.actionsBubbleGap)
        .maxHeightGetter($menuHeight)
    }

    @ViewBuilder
    private func menuRows(_ actions: [ActionEnum]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
            ContextMenuActionRow(
                title: action.title(),
                icon: action.icon(),
                isDestructive: action.type() == .delete,
                font: getFont ?? .system(size: 17),
                action: {
                    softTapHaptic()
                    onAction(action)
                    dismissSelf()
                }
            )
        }
    }
    
    private func filteredMenuActions() -> [ActionEnum] {
        let validActions = ActionEnum.allCases.filter { action in
            let type = action.type()
            switch type {
            case .edit:
                return message.type == .text && message.user.isCurrentUser && message.publicationAttachment == nil && message.sticker == nil && message.videoNote == nil
            case .delete:
                return message.user.isCurrentUser && message.isDeliverableStatus
            case .reply, .forward:
                // Удалённый модерацией чужой кружок: в меню только «Удалить» (§8.8).
                if let note = message.videoNote, note.isRemoved, !message.user.isCurrentUser { return false }
                return true
            case .copy:
                // Стикер копировать нечего (текста у него нет).
                return (message.type == .text || message.type == .url) && message.sticker == nil && message.videoNote == nil
            case .information:
                return message.user.isCurrentUser &&
                isGroup &&
                message.isDeliverableStatus
            @unknown default:
                return false
            }
        }
        
        // Separate actions into non-destructive and destructive (delete)
        let (destructive, nonDestructive) = validActions.partitioned { $0.type() == .delete }
        return nonDestructive + destructive
    }

    private func dismissSelf() {
        if keyboardState.isShown { keyboardState.resignFirstResponder() }
        transitionViewState(to: .dismiss)
        let delay = didReact ? Int(animationDuration * 1333) : Int(animationDuration * 1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            isShowingMenu = false
            onDismissed()
            dismiss()
        }
    }
    
    private func softTapHaptic() {
        // Single soft impact for menu taps
        let gen = UIImpactFeedbackGenerator(style: .soft)
        gen.prepare()
        gen.impactOccurred()
    }
}

enum ViewState {
    case initial
    case prepare
    case original
    case ready
    case keyboard
    case dismiss
}

enum MenuStyle {
    case vStack
    case scrollView(height: CGFloat)
    
    func height(_ maxMenuHeight: CGFloat) -> CGFloat {
        switch self {
        case .vStack:
            return maxMenuHeight
        case .scrollView(let height):
            return height
        }
    }
}

// - MARK: Debug Views
extension MessageMenu {
    @ViewBuilder
    func debugViews() -> some View {
        // Original Message Frame
        Rectangle()
            .fill(.clear)
            .border(.blue)
            .frame(width: cellFrame.width, height: cellFrame.height)
            .position(x: cellFrame.midX, y: cellFrame.midY)
        // Current Message Frame
        Rectangle()
            .fill(.clear)
            .border(.purple)
            .frame(width: messageFrame.width, height: messageFrame.height)
            .position(x: messageFrame.midX, y: messageFrame.midY)
        // Target
        Rectangle()
            .fill(.orange)
            .frame(width: messageMenuFrame.width, height: 2)
            .position(x: messageMenuFrame.midX, y: messageMenuFrame.midY)
        // Top Safe Area
        Rectangle()
            .fill(.red)
            .opacity(0.3)
            .frame(width: chatViewFrame.width, height: UIApplication.safeArea.top)
            .position(x: chatViewFrame.midX, y: UIApplication.safeArea.top / 2)
        // Bottom Safe Area
        Rectangle()
            .fill(.red)
            .opacity(0.3)
            .frame(width: chatViewFrame.width, height: UIApplication.safeArea.bottom)
            .position(x: chatViewFrame.midX, y: chatViewFrame.height - (UIApplication.safeArea.bottom / 2))
    }
}

struct MenuContainerModifier: ViewModifier {
    @State var style: MenuStyle
    var background: Color
    
    func body(content: Content) -> some View {
        switch style {
        case .vStack:
            content
        case .scrollView(let height):
            ScrollView {
                content
            }
            .scrollIndicatorsHidden()
            .frame(height: height)
            .background(background)
        }
    }
}

struct ScrollContainerModifier: ViewModifier {
    var style: MenuStyle
    var viewState: ViewState
    var background: Color
    var onTap: () -> Void
    
    func body(content: Content) -> some View {
        if (viewState != .initial || viewState != .prepare), case .scrollView(let height) = style {
            ScrollView {
                content
            }
            .clipped()
            .frame(maxHeight: height)
            .onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}

extension View {
    func overflowContainer(_ style: MenuStyle, viewState: ViewState, background: Color = .clear, onTap: @escaping () -> Void) -> some View {
        modifier(ScrollContainerModifier(style: style, viewState: viewState, background: background, onTap: onTap))
    }
    
    func menuContainer(_ style: MenuStyle, background: Color = .clear) -> some View {
        modifier(MenuContainerModifier(style: style, background: background))
    }
}
