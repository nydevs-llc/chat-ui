//
//  PinchZoomContext.swift
//  PhotoGallery
//
//  Created by Boris on 15.11.2023.
//

import SwiftUI

struct PinchZoomContext<Content: View>: View {
    @State private var offset: CGPoint = .zero
    @State private var scale: CGFloat = 0
    @State private var scalePosition: CGPoint = .zero
    
    private var content: Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .offset(x: offset.x, y: offset.y)
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZoomGesture(size: size, offset: $offset, scale: $scale, scalePosition: $scalePosition)
                }
            }
            .scaleEffect(1 + (scale < 0 ? 0 : scale), anchor: .init(x: scalePosition.x, y: scalePosition.y))
            .zIndex(scale != 0 ? 1000 : 0)
            .onChange(of: scale) { _, newValue in
                guard scale == -1 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    scale = 0
                }
            }
    }
    
}

extension View {
    func addPinchZoom() -> some View {
        PinchZoomContext {
            self
        }
    }
}
