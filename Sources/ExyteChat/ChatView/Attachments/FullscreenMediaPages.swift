//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import SwiftUI

struct FullscreenMediaPages: View {
    
    @Environment(\.chatTheme) private var theme
    @Environment(\.mediaPickerTheme) var pickerTheme
    
    @StateObject var viewModel: FullscreenMediaPagesViewModel
    @State private var isSaving = false

    var safeAreaInsets: EdgeInsets
    var onClose: () -> Void
    var onSave: (Int) -> Void
    
    var body: some View {
        ZStack {
            // Background dimming based on drag offset
            Color.black
                .opacity(max((200.0 - viewModel.offset.height) / 200.0, 0.5))
            
            // Main fullscreen content
            VStack {
                // This solution is NOT compatible with our needs - [TabView x video]
                TabView(selection: $viewModel.index) {
                    ForEach(viewModel.attachments.enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                        AttachmentsPage(attachment: attachment)
                            .tag(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
                            .addPinchZoom()
                    }
                }
                .environmentObject(viewModel)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .offset(viewModel.offset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged(handleDragChanged)
                    .onEnded(handleDragEnded)
            )
            .onTapGesture {
                withAnimation {
                    viewModel.showMinis.toggle()
                }
            }
            
            // Bottom thumbnails view
            VStack(spacing: 0) {
                Spacer()
                
                if viewModel.showMinis {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 2) {
                                ForEach(viewModel.attachments.enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                                    AttachmentCell(attachment: attachment) { _ in
                                        withAnimation {
                                            viewModel.index = index
                                        }
                                    }
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(4)
                                    .clipped()
                                    .id(index)
                                    .overlay {
                                        if viewModel.index == index {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(theme.colors.sendButtonBackground, lineWidth: 2)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding([.top, .horizontal], 12)
                            .padding(.bottom, safeAreaInsets.bottom + 12)
                        }
                        .onAppear {
                            proxy.scrollTo(viewModel.index)
                        }
                        .onChange(of: viewModel.index) { newValue in
                            withAnimation {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                    .background(
                        Rectangle()
                            .fill(.ultraThickMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
            .offset(viewModel.offset)
        }
        .ignoresSafeArea()
        
        .overlay(alignment: .top) {
            if viewModel.showMinis {
                ZStack {
                    // Top blurred background with shadow
                    Rectangle()
                        .fill(.ultraThickMaterial)
                        .frame(height: 40 + safeAreaInsets.top)
                        .edgesIgnoringSafeArea(.top)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    HStack {
                        // Close button
                        Button(action: {
                            performMediumHaptic()
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .padding(5)
                                .foregroundColor(.primary)
                        }
                        .padding(.leading, 15)
                        
                        Spacer()
                        
                        // Current page indicator
                        Text("\(viewModel.index + 1)/\(viewModel.attachments.count)")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Right side action buttons
                        HStack(spacing: 20) {
                            if viewModel.attachments[viewModel.index].type == .video {
                                (viewModel.videoPlaying ? theme.images.fullscreenMedia.pause : theme.images.fullscreenMedia.play)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .padding(5)
                                    .foregroundColor(.primary)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.toggleVideoPlaying()
                                    }
                                
                                (viewModel.videoMuted ? theme.images.fullscreenMedia.mute : theme.images.fullscreenMedia.unmute)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.primary)
                                    .frame(width: 24, height: 24)
                                    .padding(5)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.toggleVideoMuted()
                                    }
                            }
                            
                            Group {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                        .frame(width: 24, height: 24)
                                        .padding(5)
                                } else {
                                    theme.images.messageMenu.save
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.primary)
                                        .frame(width: 24, height: 24)
                                        .padding(5)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            performMediumHaptic()
                                            isSaving = true
                                            onSave(viewModel.index)
                                        }
                                }
                            }
                        }
                        .padding(.trailing, 10)
                    }
                    .padding(.top, safeAreaInsets.top)
                    .frame(height: 60)
                }
            }
        }
    }
    
    func performMediumHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    func handleDragChanged(_ value: DragGesture.Value) {
        guard abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return }
        if viewModel.showMinis {
            viewModel.showMinis = false
        }
        viewModel.offset = closeSize(from: value.translation)
    }
    
    func handleDragEnded(_ value: DragGesture.Value) {
        if value.translation.height >= 100 {
            onClose()
        } else {
            withAnimation(.spring()) {
                viewModel.showMinis = true
                viewModel.offset = .zero
            }
        }
    }
}

private extension FullscreenMediaPages {
    // Helper to calculate vertical drag offset
    func closeSize(from size: CGSize) -> CGSize {
        CGSize(width: 0, height: max(size.height, 0))
    }
}
