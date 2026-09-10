//
//  ResizeHandle.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The draggable divider between the word list and the reading pane.
///
/// The visible line stays hairline-thin, but the grab area is widened so it can
/// actually be caught with the mouse.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultWidth: Double

    private static let grabWidth: Double = 9

    @State private var widthAtDragStart: Double?
    @State private var isActive = false

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: Self.grabWidth)
                    .contentShape(Rectangle())
                    .applyColumnResizePointer()
                    .gesture(drag)
                    .onTapGesture(count: 2) {
                        width = defaultWidth
                    }
                    .onHover { isActive = $0 }
            }
            .overlay {
                Rectangle()
                    .fill(
                        Color.accentColor.opacity(
                            isActive || widthAtDragStart != nil ? 0.5 : 0
                        )
                    )
                    .frame(width: 2)
                    .animation(
                        .easeOut(duration: 0.12),
                        value: isActive
                    )
            }
            .accessibilityElement()
            .accessibilityLabel("Resize the word list")
            .accessibilityValue("\(Int(width)) points wide")
            .accessibilityHint("Double-tap and drag, or use the arrow keys")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    setWidth(width + 20)

                case .decrement:
                    setWidth(width - 20)

                @unknown default:
                    break
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = widthAtDragStart ?? width
                if widthAtDragStart == nil { widthAtDragStart = base }
                setWidth(base + value.translation.width)
            }
            .onEnded { _ in widthAtDragStart = nil }
    }

    private func setWidth(_ proposed: Double) {
        width = min(max(proposed, range.lowerBound), range.upperBound)
    }
}

private extension View {
    @ViewBuilder
    func applyColumnResizePointer() -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(.columnResize)
        } else {
            self
        }
    }
}
