import AppKit
import PDFKit
import WebKit

// Fork: the ways a page is kept that did nothing.
//
// - ⌘P, from the site's controls: the print sheet went to the key window,
//   which was the popover on its way out, and never appeared.
// - Printing a PDF printed WebKit's drawing of it, cut at the edges and
//   missing its images. The document itself is printed instead.
// - Print… in a page's right-click menu, as Chrome has it.
// - Download Audio and Download Video in the right-click menu: WebKit's own
//   item never asks this app's download delegate, as Download Image doesn't
//   (see ImageMenu.swift), and a player drawn by the page has none at all.
//   The page says which media was under the pointer; that is downloaded.

extension Browser {
    // The PDF bar's download button and a page's own print() are upstream's
    // now (Browser.swift); its print hands a PDF over to `print` here.

    /// The print sheet, on the browser's own window whatever is in front of it.
    /// A PDF is printed as the document it is, page for page.
    func print(_ web: WKWebView) {
        guard let window = Links.window ?? web.window else { return }
        guard web.showsPDF else { return printDrawn(web, in: window) }
        web.displayedPDF { [weak self] pdf in
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
            if let pdf, let document = PDFDocument(data: pdf),
               let job = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) {
                job.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                self?.printDrawn(web, in: window)
            }
        }
    }

    /// The page as WebKit draws it: everything but a PDF.
    private func printDrawn(_ web: WKWebView, in window: NSWindow) {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        let job = web.printOperation(with: info)
        job.view?.frame = web.bounds
        job.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}


extension WKWebView {
    /// A PDF is on show — asked of WebKit by a name outside its public
    /// framework; a page that ends in .pdf counts when it isn't answered.
    var showsPDF: Bool {
        let showing = NSSelectorFromString("_isDisplayingPDF")
        if responds(to: showing) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(method(for: showing), to: Getter.self)(self, showing)
        }
        return url?.pathExtension.lowercased() == "pdf"
    }

    /// The PDF on show, as the file it came in: fetched again by WebKit
    /// itself, with this page's own cookies, into a temporary file. The web
    /// archive won't do — for a PDF it holds the HTML WebKit draws it in.
    func displayedPDF(_ done: @escaping (Data?) -> Void) {
        guard let url, ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return done(nil) }
        if url.isFileURL { return done(try? Data(contentsOf: url)) }
        let fetch = PDFFetch(done)
        startDownload(using: URLRequest(url: url)) { download in
            download.delegate = fetch
            PDFFetch.running.insert(fetch)
        }
    }
}

// MARK: - the right-click menu

/// What the page said was under the pointer as its menu opened.
struct PageMedia {
    let src: String
    let video: Bool
    let at: Date
}

/// Told by the page, on every right-click, which audio or video was under
/// the pointer — the element itself, or one inside the player drawn around
/// it. The message arrives before the menu does.
final class MediaRelay: NSObject, WKScriptMessageHandler {
    static let name = "forkMedia"
    weak var page: PageView?

    static let watch = """
    (function () {
      if (window.__forkMedia) return;
      window.__forkMedia = true;
      function find(e) {
        var el = e.target;
        if (el && el.closest) {
          var m = el.closest('video, audio');
          if (m) return m;
        }
        // A player drawn by the page: its media is near, not under.
        for (var up = el, i = 0; up && i < 6; up = up.parentElement, i++) {
          var inside = up.querySelector && up.querySelector('video, audio');
          if (inside) return inside;
        }
        var all = document.elementsFromPoint(e.clientX, e.clientY);
        for (var j = 0; j < all.length; j++) if (/^(VIDEO|AUDIO)$/.test(all[j].tagName)) return all[j];
        return null;
      }
      document.addEventListener('contextmenu', function (e) {
        var relay = window.webkit && webkit.messageHandlers && webkit.messageHandlers.forkMedia;
        if (!relay) return;
        var m = find(e), src = '';
        if (m) {
          src = m.currentSrc || m.src || '';
          if (!src) { var s = m.querySelector('source[src]'); src = s ? s.src : ''; }
        }
        relay.postMessage({ src: src, video: !!m && m.tagName === 'VIDEO' });
      }, true);
    })();
    """

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let src = body["src"] as? String ?? ""
        MainActor.assumeIsolated {
            page?.media = src.isEmpty ? nil : PageMedia(src: src, video: body["video"] as? Bool == true, at: Date())
            page?.mediaFrame = message.frameInfo.isMainFrame
        }
    }
}

extension PageView {
    /// Print… after Reload, where Chrome has it, and a Download Audio or
    /// Download Video of this app's own in place of WebKit's.
    func forkMenu(_ menu: NSMenu) {
        if let reload = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierReload" }) {
            let print = NSMenuItem(title: "Print…", action: #selector(printFromMenu(_:)), keyEquivalent: "")
            print.target = self
            menu.insertItem(print, at: reload + 1)
        }
        let theirs = menu.items.filter { $0.identifier?.rawValue == "WKMenuItemIdentifierDownloadMediaToDisk" }
        guard let media, Date().timeIntervalSince(media.at) < 2 else { return }
        let at = theirs.first.map { menu.index(of: $0) } ?? 0
        theirs.forEach { menu.removeItem($0) }
        let item = NSMenuItem(title: media.video ? "Download Video" : "Download Audio", action: #selector(downloadMedia(_:)), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: at)
        if at == 0, menu.items.count > 1 { menu.insertItem(.separator(), at: 1) }
    }

    @objc private func printFromMenu(_ item: NSMenuItem) {
        (uiDelegate as? Browser)?.print(self)
    }

    @objc private func downloadMedia(_ item: NSMenuItem) {
        guard let media, let url = URL(string: media.src) else { return }
        let browser = uiDelegate as? Browser
        switch url.scheme?.lowercased() {
        case "http", "https":
            startDownload(using: URLRequest(url: url)) { browser?.keep($0) }
        case "blob", "data" where mediaFrame:
            // Only the page can read its own blob: a link it clicks, marked
            // to download, which WebKit hands to the download delegate.
            let js = """
            (function (src) { var a = document.createElement('a'); a.href = src;
              a.download = ''; a.style.display = 'none'; document.body.appendChild(a); a.click(); a.remove(); })
            """
            evaluateJavaScript("\(js)(\(Self.quoted(media.src)))", in: nil, in: .page) { _ in }
        default:
            browser?.announce("That media can't be downloaded")
        }
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}

/// One PDF fetched for printing: into a temporary file, read, and gone.
final class PDFFetch: NSObject, WKDownloadDelegate {
    @MainActor static var running: Set<PDFFetch> = []
    private let done: (Data?) -> Void
    private var file: URL?

    init(_ done: @escaping (Data?) -> Void) { self.done = done }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("search-print-\(UUID().uuidString).pdf")
        file = temp
        completionHandler(temp)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let data = file.flatMap { try? Data(contentsOf: $0) }
        finish(data?.starts(with: Data("%PDF".utf8)) == true ? data : nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(nil)
    }

    private func finish(_ data: Data?) {
        if let file { try? FileManager.default.removeItem(at: file) }
        MainActor.assumeIsolated {
            done(data)
            PDFFetch.running.remove(self)
        }
    }
}
