import SwiftUI
import AppKit

// Fork: the column's edge as a real view. Drawn by SwiftUI alone it lay under
// the column's DragStrip — a representable, and so a real view that AppKit
// asks first — and under the rows' own cursor handling, so the resize cursor
// flickered in and out and a drag moved the window instead. A view of its own
// keeps a cursor rect AppKit honours and takes the drag and double-click.

struct ColumnEdge: NSViewRepresentable {
    /// Left to right is wider for a column on the left, narrower on the right.
    let right: Bool
    let width: () -> CGFloat
    let resize: (CGFloat) -> Void
    let reset: () -> Void
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> Edge { Edge() }

    func updateNSView(_ view: Edge, context: Context) {
        view.right = right
        view.width = width
        view.resize = resize
        view.reset = reset
        view.hover = hover
    }

    final class Edge: NSView {
        var right = false
        var width: () -> CGFloat = { 0 }
        var resize: (CGFloat) -> Void = { _ in }
        var reset: () -> Void = {}
        var hover: (Bool) -> Void = { _ in }

        private var from: (x: CGFloat, width: CGFloat)?
        private var tracking: NSTrackingArea?

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }

        override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
        override func mouseEntered(with event: NSEvent) { hover(true) }
        override func mouseExited(with event: NSEvent) { if from == nil { hover(false) } }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                from = nil
                reset()
                return
            }
            from = (event.locationInWindow.x, width())
        }

        override func mouseDragged(with event: NSEvent) {
            guard let from else { return }
            NSCursor.resizeLeftRight.set()
            let moved = event.locationInWindow.x - from.x
            resize(from.width + (right ? -moved : moved))
        }

        override func mouseUp(with event: NSEvent) {
            from = nil
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            if !inside { hover(false) }
        }
    }
}
