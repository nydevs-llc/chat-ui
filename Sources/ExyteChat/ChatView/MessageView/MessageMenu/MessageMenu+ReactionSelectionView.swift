//
//  ReactionSelectionView.swift
//  Chat
//
//  Created by Bohdan Yankivskyi on 05.08.2025.
//

import SwiftUI

struct ReactionSelectionView: View {
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    static let maxSelectionRowWidth: CGFloat = 400

    @StateObject private var keyboardState = KeyboardState()

    @StateObject var viewModel: ChatViewModel
    
    @State private var selectedEmoji: String = ""
    @FocusState private var emojiEntryIsFocused: Bool
    
    @State private var emojis: [String] = []

    @State private var placeholder: String = ""
    @State private var maxWidth: CGFloat = ReactionSelectionView.maxSelectionRowWidth
    @State private var maxSelectionRowWidth: CGFloat = ReactionSelectionView.maxSelectionRowWidth
    @State private var maxHeight: CGFloat? = nil
    @State private var opacity: CGFloat = 1.0
    @State private var xOffset: CGFloat = 0.0
    @State private var yOffset: CGFloat = 0.0
    @State private var viewState: ViewState = .initial
    
    @State private var bubbleDiameter: CGFloat = .zero
    
    var backgroundColor: Color
    var selectedColor: Color
    var animation: Animation
    var animationDuration: Double
    var currentReactions: [Reaction]
    var customReactions: [ReactionType]?
    var allowEmojiSearch: Bool
    var alignment: MessageMenuAlignment
    var leadingPadding: CGFloat
    var trailingPadding: CGFloat
    var reactionClosure: ((ReactionType?) -> Void)
    var alignWithMenuStart: Bool = false
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 10
    private let bubbleDiameterMultiplier: CGFloat = 1.5
    /// Scales only the emoji glyph inside the bubble (relative to bubbleDiameter)
    var emojiGlyphScale: CGFloat = 0.72

    /// Scales the launcher icon (search/xmark) relative to bubbleDiameter
    var launcherIconScale: CGFloat = 0.66

    var uiScale: CGFloat = 1.0
    private var hPad: CGFloat { horizontalPadding * uiScale }
    private var vPad: CGFloat { verticalPadding * uiScale }
//    private let searchSymbolName: String = "plus.circle"//"face.smiling"
  
    private var searchSymbolName: String {
        if UIImage(systemName: "plus.circle") != nil {
            return "plus.circle"
        }
        return "plus" 
    }
    
    var body: some View {
        let currentEmojiReactions = currentReactions.compactMap(\.emoji)
        // Compact when not .row (covers .search and .picked)
        let isCompact = (viewState != .row && viewState != .initial)
        let horizontalPadding = !isCompact ? max(hPad, bubbleDiameter/2 + 6) : 0

        HStack(spacing: 0) {
            leadingPaddingView()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: hPad) {
                    // Center the single bubble in compact states
                    if isCompact { Spacer(minLength: 0) }

                    ForEach(emojis.indices, id: \.self) { index in
                        Button {
//                            transitionToViewState(.picked(emojis[index]))
                                reactionClosure(.emoji(emojis[index]))
                        } label: {
                            emojiView(
                                emoji: emojis[index],
                                isSelected: currentEmojiReactions.contains(emojis[index])
                            )
                            .frame(width: bubbleDiameter, height: bubbleDiameter, alignment: .center)
                        }
                    }

                    if allowEmojiSearch, viewState.needsSearchButton {
                        additionalEmojiPickerView()
                            .frame(width: bubbleDiameter, height: bubbleDiameter, alignment: .center)
                            .onChange(of: selectedEmoji) { _ in
                                transitionToViewState(.picked(selectedEmoji))
                            }
                            .onChange(of: emojiEntryIsFocused) { _ in
                                if emojiEntryIsFocused { transitionToViewState(.search) }
                            }
                    }

                    if isCompact { Spacer(minLength: 0) }
                }
                .padding(.vertical, vPad)
                .padding(.horizontal, horizontalPadding)
                // Give the inner row a fixed box only in compact modes so Spacers can center content
                .frame(
                    width: isCompact ? maxWidth : nil,
                    height: isCompact ? maxHeight : nil,
                    alignment: .center
                )
            }
            // убрано в пользу padding
//            .contentMargins(
//                .horizontal,
//                !isCompact ? max(hPad, bubbleDiameter/2 + 6) : 0,
//                for: .scrollContent
//            )
            .scrollIndicators(.hidden)
            .padding(.horizontal, isCompact ? 0 : 2)          // key: no extra inset in compact
            .modifier(InteriorRadialShadow(color: viewState.needsInteriorShadow ? backgroundColor : .clear))
            .frame(width: maxWidth, height: maxHeight, alignment: .center) // key: fixed box

            .background(Capsule(style: .continuous).foregroundStyle(backgroundColor))
            .clipShape(Capsule(style: .continuous))
    
            .opacity(opacity)
//            .overlay(alignment: alignment == .left ? .topLeading : .topTrailing) {
//                if emojiEntryIsFocused {
//                    // draw above without affecting layout
////                    closeButton(color: backgroundColor)
////                        .transition(.scaleAndFade)
//                }
//            }
            
            trailingPaddingView()
        }
        .offset(x: xOffset, y: yOffset)
        .onAppear { transitionToViewState(.row) }
        .onChange(of: keyboardState.isShown) { _ in
            if !keyboardState.isShown && viewState == .search {
                transitionToViewState(.row)
            }
        }
    }
    
    @ViewBuilder
    func emojiView(emoji:String, isSelected:Bool) -> some View {
        let fontSize = bubbleDiameter * 0.75
        if isSelected {
            Text(emoji)
                .font(.system(size: fontSize, weight: .regular))
                .background(
                    Circle()
                        .fill(selectedColor)
                        .shadow(radius: 1)
                        .padding(-vPad + 4)
                )
        } else {
            Text(emoji)
                .font(.system(size: fontSize, weight: .regular))
        }
    }

    @ViewBuilder
    func additionalEmojiPickerView() -> some View {
        ZStack {
            EmojiTextField(placeholder: placeholder, text: $selectedEmoji)
                .font(.system(size: bubbleDiameter * 0.62))
                .focused($emojiEntryIsFocused)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .textSelection(.disabled)
                .opacity(0.01)
                .allowsHitTesting(false)
                .onChange(of: selectedEmoji) { _ in
                    selectedEmoji = selectedEmoji.lastEmojiOrEmpty()
                    if !selectedEmoji.isEmpty {
                        transitionToViewState(.picked(selectedEmoji))
                    }
                }

            Image(systemName: emojiEntryIsFocused ? "xmark" : searchSymbolName)
                .font(.system(size: emojiEntryIsFocused ? bubbleDiameter * 0.55 : bubbleDiameter * 0.85, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .contentShape(Circle())
                .onTapGesture {
                    if emojiEntryIsFocused {
                        // tap on xmark closes search mode
                        reactionClosure(nil)
                        transitionToViewState(.row)
                    } else {
                        // open emoji keyboard
                        emojiEntryIsFocused = true
                    }
                }
        }
        .frame(width: bubbleDiameter, height: bubbleDiameter)
    }

    @ViewBuilder
    func leadingPaddingView() -> some View {
        if alignWithMenuStart {
            EmptyView()
        } else {
            if alignment == .left {
                Color.clear.viewWidth(max(1, leadingPadding - 8))
                Spacer()
            } else {
                let additionalPadding = max(0, UIScreen.main.bounds.width - maxSelectionRowWidth - trailingPadding)
                Color.clear.viewWidth(additionalPadding + trailingPadding * 3)
            }
        }
    }

    @ViewBuilder
    func trailingPaddingView() -> some View {
        if alignWithMenuStart {
            EmptyView()
        } else {
            if alignment == .right {
                Spacer()
                Color.clear.viewWidth(trailingPadding)
            } else {
                let additionalPadding = max(0, UIScreen.main.bounds.width - maxSelectionRowWidth - leadingPadding)
                Color.clear.viewWidth(additionalPadding + trailingPadding * 3)
            }
        }
    }

    private func calcMaxSelectionRowWidth() -> CGFloat {
        var emojiCount = emojis.count
        if allowEmojiSearch { emojiCount += 1 }
        let contentWidth = CGFloat(emojiCount) * (bubbleDiameter + hPad) + hPad * 2
        let screenWidth = UIScreen.main.bounds.width
        let maxAllowedWidth = screenWidth * 0.8
        return min(contentWidth, maxAllowedWidth)
    }
    
    private func transitionToViewState(_ state:ViewState) {
        guard state != viewState else { return }
        let previousState = viewState
        viewState = state
        switch viewState {
        case .initial:
            self.transitionToViewState(.row)
            return
        case .row:
            bubbleDiameter = dynamicTypeSize.bubbleDiameter() * uiScale
            emojiEntryIsFocused = false
            withAnimation(animation) {
                emojis = getEmojis()
                maxSelectionRowWidth = calcMaxSelectionRowWidth()
                maxWidth = maxSelectionRowWidth
                maxHeight = nil
                xOffset = CGFloat.leastNonzeroMagnitude
                yOffset = CGFloat.leastNonzeroMagnitude
            }
        case .search:
            withAnimation(animation) {
                emojis = []
                maxWidth = bubbleDiameter * bubbleDiameterMultiplier
                maxHeight = bubbleDiameter * bubbleDiameterMultiplier
                xOffset = getXOffset()
                yOffset = getYOffset()
            }
        case .picked(let emoji):
            withAnimation(animation) {
                emojis = [emoji]
                maxWidth = bubbleDiameter * bubbleDiameterMultiplier
                maxHeight = bubbleDiameter * bubbleDiameterMultiplier
                xOffset = getXOffset()
                yOffset = getYOffset()
            }
            
            switch previousState {
            case .row:
                Task {
                    try await Task.sleep(for: .milliseconds(animationDuration * 1333))
                    reactionClosure(.emoji(emoji))
                }
            case .search:
                emojiEntryIsFocused = false
                Task {
                    try await Task.sleep(for: .milliseconds(animationDuration * 666))
                    reactionClosure(.emoji(selectedEmoji))
                }
            case .initial, .picked:
                break
            }
        }
    }
    
    private func getEmojis() -> [String] {
        if let customReactions, !customReactions.isEmpty { return customReactions.map { $0.toString } }
        return defaultEmojis()
    }
    
    /// Constructs the default reaction list, containing any reactions the current user has already applied to this message
    /// - Returns: A list of emojis that the ReactionSelectionView should display
    /// - Note: We include the current senders past reactions so it's easier for the sender to remove / undo a reaction if the developer supports this.
    private func defaultEmojis() -> [String] {
        var standard = ["👍", "👎"]
        let current = currentReactions.compactMap(\.emoji).filter {
            !standard.contains($0)
        }
        standard.insert(contentsOf: current, at: 2)
        var extra = [ "❤️", "🤣", "‼️", "❓", "🥳", "💪", "🔥", "💔", "😭"]
        while !extra.isEmpty, standard.count < max(10, current.count + 2) {
            if let new = extra.firstIndex(where: { !standard.contains($0) }) {
                standard.append( extra.remove(at: new) )
            } else {
                break
            }
        }
        return Array(standard)
    }
    
    /// Calculates the X axis offset of the ReactionSelectionView for the current ViewState
    /// - Returns: The X axis offset for the ReactionSelectionView
    /// - Note: If the messageFrame's width is equal to, or larger than, the Screens width then we skip the offset animation
    /// - Note: This also prevents the offset animation from occuring when the user uses a custom message builder
    private func getXOffset() -> CGFloat {
        guard viewModel.messageFrame.width < UIScreen.main.bounds.width else { return .leastNonzeroMagnitude }
        switch viewState {
        case .initial, .row:
            return .leastNonzeroMagnitude
        case .search, .picked:
            if alignment == .left {
                let additionalPadding = max(0, UIScreen.main.bounds.width - maxSelectionRowWidth - leadingPadding) - UIApplication.safeArea.leading
                return -((UIScreen.main.bounds.width - (additionalPadding + trailingPadding * 3) - (bubbleDiameter * 0.8)) - viewModel.messageFrame.maxX)
            } else {
                let additionalPadding = max(0, UIScreen.main.bounds.width - maxSelectionRowWidth - trailingPadding) - UIApplication.safeArea.leading
                return viewModel.messageFrame.minX - ((additionalPadding + trailingPadding * 3) + (bubbleDiameter * 0.8))
            }
        }
    }

    /// Calculates the Y axis offset of the ReactionSelectionView for the current ViewState
    /// - Returns: The Y axis offset for the ReactionSelectionView
    /// - Note: If the messageFrame's width is equal to, or larger than, the Screens width then we skip the offset animation
    /// - Note: This also prevents the offset animation from occuring when the user uses a custom message builder
    private func getYOffset() -> CGFloat {
        guard viewModel.messageFrame.width < UIScreen.main.bounds.width else { return .leastNonzeroMagnitude }
        switch viewState {
        case .initial, .row:
            return .leastNonzeroMagnitude
        case .search, .picked:
            return bubbleDiameter / 1.5
        }
    }
}

extension ReactionSelectionView {
    /// ReactionSelectionView View State
    private enum ViewState:Equatable {
        case initial
        /// A horizontal list of default reactions to select from
        /// Placement: above the messageFrame
        case row
        /// A placeholder emoji view that launches the emoji keyboard that allows the sender to select a custom emoji
        /// Placement: At the top corner of the messageFrame or directly above it when using a custom messageBuilder
        case search
        /// A temporary emoji view that animates into it's final position before the message menu is dismissed
        /// Placement: At the top corner of the messageFrame or directly above it when using a custom messageBuilder
        case picked(String)
        
        var needsInteriorShadow:Bool {
            switch self {
            case .row:
                return true
            case .search, .picked, .initial:
                return false
            }
        }
        
        var needsSearchButton:Bool {
            switch self {
            case .row, .search, .initial:
                return true
            case .picked:
                return false
            }
        }
        
        var isPicked:Bool {
            switch self {
            case .picked:
                return true
            default:
                return false
            }
        }
    }
}

private extension String {
    func lastEmojiOrEmpty() -> String {
        let emojis = self.filter { $0.isEmoji }
        return emojis.last.map(String.init) ?? ""
    }
}
private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji }
    }
}

internal struct InteriorRadialShadow: ViewModifier {
    var color:Color
    let innerRadius: CGFloat = 14
    let outerRadius: CGFloat = 5
    
    func body(content: Content) -> some View {
        content.overlay(
            ZStack {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(
                            RadialGradient(gradient: Gradient(colors: [.clear, color]), center: .center, startRadius: proxy.size.width / 2 - innerRadius, endRadius: proxy.size.width / 2 - outerRadius)
                        )
                        .overlay(
                            RadialGradient(gradient: Gradient(colors: [.clear, color]), center: .center, startRadius: proxy.size.width / 2 - innerRadius, endRadius: proxy.size.width / 2 - outerRadius)
                                .clipShape(Capsule(style: .continuous))
                        )
                }
                Capsule(style: .continuous)
                    .stroke(color, lineWidth: 3)
            }
            .allowsHitTesting(false)
        )
    }
}

//#Preview {
//    VStack {
//        ReactionSelectionView(
//            viewModel: ChatViewModel(),
//            backgroundColor: .gray,
//            selectedColor: .blue,
//            animation: .linear(duration: 0.2),
//            animationDuration: 0.2,
//            currentReactions: [
//                Reaction(
//                    user: .init(
//                        id: "123",
//                        name: "Tim",
//                        avatarURL: nil,
//                        isCurrentUser: true
//                    ),
//                    type: .emoji("❤️")
//                ),
//                Reaction(
//                    user: .init(
//                        id: "123",
//                        name: "Tim",
//                        avatarURL: nil,
//                        isCurrentUser: true
//                    ),
//                    type: .emoji("👍")
//                )
//            ],
//            allowEmojiSearch: true,
//            alignment: .left,
//            leadingPadding: 20,
//            trailingPadding: 20
//        ) { selectedEmoji in
//            if let selectedEmoji = selectedEmoji {
//                print("\(selectedEmoji)")
//            }
//        }
//    }
//    .frame(width: 400, height: 100)
//}
