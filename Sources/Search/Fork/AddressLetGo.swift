import AppKit

// Fork: the column's address is let go by a click anywhere else in the
// window — the page, the column, the card it slides out as. Only a click on
// the page did it before (a catch laid over the page), and not every click
// there reached the catch; one in the column never did, so the caret stayed
// in the address until another tab was picked.

@MainActor
private var letGo: Any?
/// Whether the press that the release belongs to began in the field, as a
/// drag across its text does.
@MainActor
private var pressedInField = false

extension Browser {
    func followAddressClicks() {
        guard letGo == nil else { return }
        letGo = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, self.prefs.sidebar, self.editing, self.active?.isBlank == false,
                  let window = event.window, window === Links.window
            else { return event }
            let inField = Browser.inAddress(event, window: window)
            if event.type == .leftMouseDown {
                pressedInField = inField
                return event
            }
            // After the click has done its own work — a suggestion picked
            // under the field submits, and that ends the edit first.
            if !inField, !pressedInField {
                DispatchQueue.main.async { if self.editing { self.dismiss() } }
            }
            pressedInField = false
            return event
        }
    }

    /// The press is on the field being typed into: the text field the field
    /// editor is working for, or anything inside it.
    private static func inAddress(_ event: NSEvent, window: NSWindow) -> Bool {
        guard let editor = window.firstResponder as? NSTextView,
              let field = editor.delegate as? NSTextField,
              let content = window.contentView
        else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        guard let hit = content.hitTest(point) else { return false }
        return hit === field || hit === editor || hit.isDescendant(of: field)
    }
}
