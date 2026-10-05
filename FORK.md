# This fork

A fork of [driceroland/Search](https://github.com/driceroland/Search) with an
Arc-style sidebar: per-space colours and bookmarks, the address in the column,
and a floating folded column. The tab strip across the top is left as upstream
has it.

## How it is kept

- `main` is upstream plus one commit per feature, in the order below. Nothing
  else. Every commit builds on its own.
- Fork code lives in `Sources/Search/Fork/`. Upstream files only carry the
  hooks listed per feature, and each hook is marked with a `Fork:` comment.
- Updating: `git fetch upstream && git rebase upstream/main` (or a release
  tag), then `swift build`. `git config rerere.enabled true` remembers how a
  conflict was resolved.
- `README.md` and `CONTRIBUTING.md` each carry a fork note at the very top,
  and are otherwise upstream's; keep those notes there on a sync.
- When upstream ships something that does the same job, compare, and if theirs
  is as good, drop that commit (`git rebase -i`) or rebuild it on theirs. The
  "Upstream overlap" column says where to look.
- Releases are tagged `VERSION-fork.N` (`1.0.4-fork.1`); `VERSION` stays
  upstream's.

## Features

Base: upstream `v1.0.4` (`3ef8cb5`, "Search 1.0.4").

| # | Commit | Fork files | Hooks in upstream files | Upstream overlap |
|---|---|---|---|---|
| 1 | Pop-ups stand on a nearly solid ground | `ForkDesign.swift` | `.popGround()` on each popover (Extensions, SpaceSwipe, `BookmarkDoor`'s list and card) and the site card | — |
| 2 | A space wears a colour of its own, and an emoji or a symbol (and later: Soft and Deep tones) | `SpaceThemes.swift` | `Space.tone`; two icons in `Spaces.icons`; `SpaceDot` and `SpaceMenu` draw `SpaceGlyph` | #262, #231 |
| 3 | Each space keeps its own bookmarks | `BookmarksPerSpace.swift` | `Bookmarks` stores `[space: list]` (load/save read the old single list); `use` on start and switch in the window in front, and in `Front.set` when another window comes to the front; `forget` on delete | — |
| 4 | Folders you make, and pages filed into them | `BookmarkFolders.swift` | On upstream's folders (1.0.4): `Bookmarks.reveal`; `detach`/`place`/`holds` not private; New Folder… in the Bookmarks menu and the list's foot (`askNewFolder`); tab menu › Add to Bookmarks | upstream folders #354 |
| 5 | A bookmark opens as a page of its own (and later: clicked again, it keeps its place) | `BookmarkPages.swift` | `Tab.bookmark`, `Tab.aim`, `Session.Entry.bookmark`, `Browser.openBookmark`; `filedLast` after `reconcilePins` and in `arrangeGroupedTabs`; `tabs(in:)` and `shownTabs` leave them out; restore/close/move/insert keep to `rowTabs`/`rowEnd`; strip draws `rowTabs` | — |
| 6 | The column wears its space's colour; the page is a card | `ColumnColour.swift` | Column background and colour scheme; row colours via `SideTone`/`Palette.quiet`; `ContentView` frame and rounded page, gutters by `sideOnRight`; `StageView.round`; window colour | #262, #231 |
| 7 | The column's first rows: lights with back/forward/reload, then the address | `SideAddress.swift`, `ExtensionsInline.swift` | `Lights.retarget` (and `Lights.centre` from it); `OfferList`; `AddressField(point:prompt:)`; `SiteCard(padded:reader:)` and public Row/Header/Separator; `Extensions.anchor(for:)` falls back to `fallbackAnchor`; ⌘L unfolds; raised field only in strip layout; `sideMin` 200; pin gap 6; `./bench site PATH controls` | #262, #298 |
| 8 | Bookmarks in the column, in folders that open in place (and later: open folders kept in `Bookmarks.opened`; folded under the space's name) | `SideMarks.swift` | `SideBar(bookmarks:)` and its folder state; `rowsEnd` counts them; tab rows file on drag; the foot's bookmark door is gone in the column | #262 |
| 9 | The column's foot: library and downloads, spaces, new space | `SideFoot.swift` | `Loot.hauls`; the download delegate calls `loot.start/name/end` beside upstream's `fetches`; Theme… on the space name; `FetchDoor` not in the column's foot | #330 |
| 10 | A folded column shows a handle on its edge | `FoldedColumn.swift` | `Fold` tracks `edgeNear` and overlays `SideHandle` | #256, #243 |
| 11 | The folded column floats as a card, lights inside it | `FoldedColumn.swift` | Fold styles the peeking column; `Lights.nudge`; reach includes `Fold.inset` | #252 |
| 12 | Import another browser's profiles, each into a space | `ProfileImport.swift` | On upstream's per-profile readers: `Chromium.read(_:profile:passphrase:)`; `safeStorage` not private; Aside in `Chromium.known`; File › Import Profiles into Spaces…; `./bench profiles` | Bring Things Over (1.0.4) |
| 13 | Closing the last open page lands on a new tab (see 31) | `LastTabClosed.swift` | `Browser.close` asks `closesLastPage` | — |
| 14 | Site icons follow the column's tone | `IconSurface.swift` | `Favicons.dark` asks `surfaceDark`; `Browser.follow` calls `followIconSurface`; `relook` not private | — |
| 15 | A site icon with nothing visible in it is no icon | `IconInk.swift` | `Favicons.square` and `known` check `hasInk` | — |
| 16 | A build without Apple's passkey entitlement never offers passkeys | — | `Preferences` offers passkeys only when possible | — |
| 17 | Bug fixes: sidebar edge, printing and PDFs, media downloads, address in the card | `ColumnEdge.swift`, `SavingPages.swift`, `AddressLetGo.swift` | Side's `edge` uses `ColumnEdge` (drag far past the minimum folds); `printPage` → `print(_:)`; `PageView.forkMenu` (Print…, Download Audio/Video) with `MediaRelay`; `edit()` peeks the folded column; `Fold` holds for `browser.editing`; `Browser.follow` → `followAddressClicks`. The PDF bar's save and the docked inspector are upstream's now | #290, #278 (both in 1.0.4) |
| 18 | Every tab, including the active tab, shows a preview beside the column | `TabPreview.swift` | Row and pin `onHover`; `Browser.select` hides it; `Tab.coverPicture` | #24 (upstream's ⌃Tab switcher is another thing) |
| 19 | Loading, said quietly | `Loading.swift` | `LoadLine` over the stage; `ProgressRing` in place of `Ring` in the column, the strip and the pins | — |
| 20 | The keychain asks as little as it can | `QuietKeychain.swift` | `build.sh` signs with "Search Local Signing" when there is no Developer ID; `Vault.login(from:)` reads no secret and `secret(for:)` reads the one used; the sign-in check reads one; imports add only accounts not kept; the import sheet chooses what to bring. Upstream's list without secrets (`Kept`) is kept as it is | #237 (in 1.0.4) |
| 21 | Session-only sign-ins outlast quitting | `SessionCookies.swift` | `Browser.init` calls `followSessionCookies` (first window); `didFinish` calls `SessionCookies.soon`; `Links.applicationShouldTerminate` waits for `keep` | — |
| 22 | Long extension names are cut in the site menu | `ExtensionsInline.swift` | — | — |
| 23 | A keyword and a space searches that site, its name in the field | `SearchKeywords.swift` | On upstream's site shortcuts (`Keyword`, Settings › General): `searchAliases` reads `prefs.keywords`; the fork's old `search.aliases` move over once (`withForkKeywords`); `Browser.searchAlias`, cleared where the field starts over; `submit` searches the keyword's site; ⌫ on empty gives it back | #188 (in 1.0.4) |
| 24 | Clear closes the tabs under New Tab | `ClearLoose.swift` | The column's rows use `looseRule` above New Tab | — |
| 25 | Pins show selected, open and put down | — | `PinSquare`: fill and border when selected, no fill when open, grey when put down | — |
| 26 | Bookmark rows show open and closed | `SideMarks.swift` | `Preferences.strikeClosedMarks` and `greysClosed` with their switches in Settings › Tabs; `PinSquare` greys by the same switch | — |
| 27 | Spaces wrap when swiped, over a column on either side | — | `SpaceSwipe.neighbor` and `slide(onward:)`; `Browser.spaceArrival`; the column's and the strip's pages show the neighbour around | #272 |
| 28 | The last page closed can leave the window empty (a setting, on) | `LastTabClosed.swift` | `Preferences.emptiesWindow`; `Browser.close` calls `afterLastPage`; `submit` calls `show`; the session keeps "nothing open" as −1 (`session`, `restoreSession`, `loadRow`, `showRow`) | — |
| 29 | A bookmark's page closed can be kept, with a minus to remove it (a setting, on) | `BookmarkPagesKept.swift`, `SideMarks.swift` | `Preferences.keepsBookmarkPages`; `Browser.close` calls `putDown(bookmarkPage:)`; `Browser.dismissBookmark`; the row's minus | — |
| 30 | README and CONTRIBUTING: the fork's notes | — | Top of `README.md` and `CONTRIBUTING.md` | — |
| 31 | With the column on the right, the lights reveal with a matching top bar | `SidePosition.swift`, `RightSidebarTopBar.swift` | `Lights.keep`'s centre stays left; the column's first row keeps no room for them on the right; `Fold` watches the top edge and shares its reveal with `ContentView.chrome`; the page slides down to make room in the coloured frame; the bar is also a drag area | Upstream's right-hand column (1.0.4) carries the lights in it |
| 32 | A PDF prints as the document it is, from the PDF bar's button too | `SavingPages.swift` | Upstream's `printFrame` delegate hands a PDF to `print(_:)` | upstream print() (1.0.4) |
| 33 | The floating video goes with you from space to space | `FloatAcrossSpaces.swift` | `Browser.floatingTab` in place of the row lookup in `land` and the floater's buttons; its return button goes via `goHome`; `leaving` not private; `enter` floats on the way out (`leaving()`, was `land()`) and `landIfHome` on arrival; `deleteSpace`/`leaveSpaces` call `landIfIn` | — |
| 34 | ⇧⌘N opens a private window: black, no bookmarks, pins or spaces, extensions on | `PrivateWindow.swift` | `Browser.isPrivate` and `privateStore`; `restoreSession` → `startPrivate`; `newTab`, `newShyTab` and `open` make `privateTab()`s; `reconcilePins` keeps none; `writeSession`/`writeRow` write nothing; `space` is `privateSpace` (black in `Spaces.nsGround`); `enter` and `SpaceSwipe` stay put; `Browsers.primary`, `closing`, `retire` and `save` leave it out; the column hides the bookmarks and the foot shows `PrivateFoot`; File menu, ⇧⌘N and Shortcuts; extensions get `hasAccessToPrivateData` and `isPrivate(for:)` | — |
| 35 | Floating videos hide site chrome and fit portrait Shorts | `FloatingVideo.swift` | `Isolate.on` adds isolation CSS and returns video dimensions; `Browser.lift` passes those to `Float.lift`, which fits the frame and aspect ratio | — |
| 36 | Sidebar bookmarks reorder above or below rows, file into folders, and move out again | `BookmarkReordering.swift`, `BookmarkFolders.swift`, `SideMarks.swift` | —; row drop indicators and Move Up/Down/Out menus use the existing persisted tree | — |
| 37 | Extensions using a browser alias start in WebKit; Proton opens sign-in and receives its popup's background replies; unsupported proxies report failure | `ExtensionCompatibility.swift` | `ExtensionShims.prepare` repairs redundant lexical aliases; permission requests return true for existing grants; Proton requests use its direct reply path instead of popup broadcasts; `Extensions.init` registers FTP/WS/WSS permission schemes; preparation stamp includes the compatibility revision; proxy settings report unavailable instead of pretending to route traffic | — |
| 38 | Native WebKit video fullscreen restores the sidebar reliably | `FullscreenPresentation.swift` | `Tab` watches WebKit's fullscreen state and stops on discard; `FormRelay` and tab selection reconcile native state instead of latching page requests; stages reconcile after WebKit returns the page; window visibility, Spaces and exit animation remain under WebKit's control | — |

Dropped at the 1.0.4 sync, as upstream now does the same: import bookmarks
from an HTML file (Bring Things Over › File…), and the column on the right
with its peek fix (Settings › Tabs; the fork keeps only its lights, 31).

Upstream PR numbers are pull requests on driceroland/Search as of 26 Sep
2026. Recheck them before each sync; merged ones are the ones to compare
against.

## Signing

Without a Developer ID, `build.sh` signs with "Search Local Signing", a
code-signing certificate made on this Mac and kept in its login keychain. It
gives every build the same identity, which the keychain goes by, so saved
passwords and kept sign-ins don't ask again after each rebuild. Without it the
build is ad-hoc, as upstream's is. To make one on another Mac: a self-signed
certificate with the code-signing extended key usage, named exactly that,
imported into the login keychain with access for `/usr/bin/codesign`.

A fork build still reads upstream's update feed, but never installs from it:
the updater only swaps in a build when this one carries a Developer ID team,
and it doesn't.

## Checking a sync

```
swift build
SEARCH_PROBE=1 .build/debug/Search &
./bench --test ui sidebar on
./bench --test column /tmp/col.png 460
./bench --test site /tmp/controls.png controls
./bench --test ui folded on && ./bench --test ui peek on && ./bench --test fold /tmp/fold.png 500
```

Compare the pictures with the ones from before the sync. The fold picture is
taken while the card may already be sliding away (no pointer over it in a
test run); run the last line again if it is cut.
