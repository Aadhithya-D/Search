import AppKit

// Keep the player's DOM intact, but remove the styles that make a fixed
// video belong to a transformed, clipped Shorts carousel rather than the viewport.
enum FloatingVideo {
    static let stylesScript = #"""
    `html.office-floating body, html.office-floating body * {
        visibility:hidden !important;
    }
    html.office-floating body video[data-office-float] {
        visibility:visible !important;
        min-width:0 !important; min-height:0 !important;
        margin:0 !important; padding:0 !important; border:0 !important;
        box-sizing:border-box !important;
    }
    html.office-floating:has([data-office-float]),
    html.office-floating body:has([data-office-float]),
    html.office-floating body *:has([data-office-float]) {
        transform:none !important; translate:none !important;
        rotate:none !important; scale:none !important;
        perspective:none !important; filter:none !important;
        backdrop-filter:none !important; contain:none !important;
        content-visibility:visible !important; will-change:auto !important;
        clip:auto !important; clip-path:none !important; mask:none !important;
    }
    html.office-floating body *:has([data-office-float]) {
        overflow:visible !important;
    }
    html.office-floating .player-timedtext, html.office-floating .player-timedtext * {
        visibility:visible !important;
    }`
    """#

    static func dimensions(_ answer: Any?) -> NSSize? {
        guard let result = answer as? [String: Any], result["status"] as? String == "floating" else { return nil }
        let width = (result["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (result["height"] as? NSNumber)?.doubleValue ?? 0
        return width > 0 && height > 0 ? NSSize(width: width, height: height) : NSSize(width: 16, height: 9)
    }

    static func size(for video: NSSize) -> NSSize {
        let ratio = video.width / video.height
        return ratio < 1 ? NSSize(width: 440 * ratio, height: 440) : NSSize(width: 440, height: 440 / ratio)
    }

    static func resizeLimit(for frame: NSRect, on screen: NSRect) -> CGFloat {
        min(screen.width, screen.height * frame.width / frame.height)
    }

    static func frame(_ remembered: NSRect, fitting size: NSSize, in screen: NSRect) -> NSRect {
        var frame = remembered
        let ratio = size.width / size.height
        if abs(frame.width / frame.height - ratio) > 0.05 { frame.size = size }
        if ratio < 1 { frame.size.width = frame.height * ratio }
        else { frame.size.height = frame.width / ratio }
        if screen.width > 0 && screen.height > 0 {
            let scale = min(1, min(screen.width / frame.width, screen.height / frame.height))
            frame.size.width *= scale
            frame.size.height *= scale
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        return frame
    }
}
