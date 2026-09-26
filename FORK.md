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
- When upstream ships something that does the same job, compare, and if theirs
  is as good, drop that commit (`git rebase -i`) or rebuild it on theirs. The
  "Upstream overlap" column says where to look.

## Features

Base: upstream `491f321` ("Roadmap: pop-ups named by their site are done").

| # | Commit | Fork files | Hooks in upstream files | Upstream overlap |
|---|---|---|---|---|
| 1 | Pop-ups stand on a nearly solid ground | `ForkDesign.swift` | `.popGround()` on each popover (Extensions, SpaceSwipe, TabBar, Side) and the site card | — |
| 2 | A space wears a colour of its own, and an emoji or a symbol | `SpaceThemes.swift` | `Space.tone`; two icons in `Spaces.icons`; `SpaceDot` and `SpaceMenu` draw `SpaceGlyph` | #262, #231 |
| 3 | Each space keeps its own bookmarks | `BookmarksPerSpace.swift` | `Bookmarks` stores `[space: list]` (load/save read the old single list); `use`/`forget` on start, switch, delete | — |
| 4 | Folders you make, and pages filed into them | `BookmarkFolders.swift` | `Bookmarks.reveal`; `detach`/`insert`/`holds` not private; ⇧⌘B files; New Folder in menus; tab menu › Add to Bookmarks | #342, #262 |
| 5 | Import bookmarks from an exported HTML file | `BookmarkHTML.swift` | Import HTML… in the Bookmarks menu, list and manager | #215 |
| 6 | A bookmark opens as a page of its own | `BookmarkPages.swift` | `Tab.bookmark`, `Tab.aim`, `Session.Entry.bookmark`, `Browser.openBookmark`; restore/close/move/step/insert keep to `rowTabs`/`rowEnd`; strip draws `rowTabs` | — |
| 7 | The column wears its space's colour; the page is a card | `ColumnColour.swift` | Column background and colour scheme; row colours via `SideTone`/`Palette.quiet`; `ContentView` frame and rounded page; `StageView.round`; window colour | #262, #231 |
| 8 | The column's first rows: lights with back/forward/reload, then the address | `SideAddress.swift`, `ExtensionsInline.swift` | `Lights.retarget`; `OfferList`; `AddressField(point:prompt:)`; `SiteCard(padded:reader:)` and public Row/Header/Separator; `Extensions.fallbackAnchor`; ⌘L unfolds; raised field only in strip layout; `sideMin` 200; pin gap 6; `./bench site PATH controls` | #262, #298 |
| 9 | Bookmarks in the column, in folders that open in place | `SideMarks.swift` | `SideBar(bookmarks:)` and its folder state; tab rows file on drag (`Carried` lets the drag leave the list); foot bookmark door and bookmarks bar removed in the column | #262 |
| 10 | The column's foot: library and downloads, spaces, new space | `SideFoot.swift` | `Loot.hauls`; download delegate calls `loot.start/name/end`; Theme… on the space name | #330 |
| 11 | The column can sit on the right | — | `Preferences.sideRight` and Settings; page, peek, hidden panel, column edge and Fold follow the side | #340, #314 |
| 12 | A folded column shows a handle on its edge | `FoldedColumn.swift` | `Fold` tracks `edgeNear` and overlays `SideHandle` | #256, #243 |
| 13 | The folded column floats as a card, lights inside it | `FoldedColumn.swift` | Fold styles the peeking column; `Lights.nudge` | #252 |
| 14 | Import another browser's profiles, each into a space | `ProfileImport.swift` | `Chromium.Source.profile`; Aside in `Chromium.known`; `read(_:passphrase:)`; `safeStorage`/`stretch` not private; File › Import from Another Browser…; `./bench profiles` | #215, #261 |

Upstream PR numbers are open pull requests on driceroland/Search as of
26 Sep 2026. Recheck them before each sync; merged ones are the ones to
compare against.

## Checking a sync

```
swift build
SEARCH_PROBE=1 .build/debug/Search &
./bench --test ui sidebar on
./bench --test column /tmp/col.png 460
./bench --test site /tmp/controls.png controls
./bench --test ui folded on && ./bench --test ui peek on && ./bench --test fold /tmp/fold.png 500
```

Compare the pictures with the ones from before the sync.
