# ZipPaint — Roadmap

Build order, smallest useful app first. Each phase ends with something
that runs.

## Phase 1 — Walking skeleton ✅

- [x] `Package.swift` + `build.sh` producing a launchable `ZipPaint.app`
- [x] Window with blank white 800×600 canvas
- [x] Menu bar with File/Edit items

## Phase 2 — The core loop ✅

The app becomes useful at the end of this phase.

- [x] Paste (Cmd+V): canvas auto-sizes to clipboard image, window resizes
- [x] Pencil tool
- [x] Copy (Cmd+C): flattened PNG+TIFF on clipboard
- [ ] **Hands-on verification needed**: screenshot → paste → scribble →
      copy → paste into another app at correct resolution

## Phase 3 — Full tool set ✅

- [x] Tool palette UI (left column, MS Paint style)
- [x] Highlighter (multiply blend, semi-transparent; auto-switches black → yellow)
- [x] Eraser (whole-stroke removal)
- [x] Line, Rectangle, Arrow
- [x] Text tool (click to place, Enter commits, Esc cancels)
- [x] Color palette bar (16 swatches) + current-color well
- [x] Stroke width picker (S / M / L)
- [x] Undo / Redo

## Phase 4 — Files & polish ✅

- [x] Open image (Cmd+O)
- [x] Save as PNG (Cmd+S)
- [x] Unsaved-markup warning before paste-over/quit
- [x] Status bar (image dimensions, tool hint)
- [x] Scrollbars for images larger than the screen

## Ideas parked for later (only if wanted)

- Fill color for rectangle
- Drag-and-drop an image file onto the canvas
- "New from clipboard" on launch

## Status log

- **2026-07-18** — Project started. Requirements gathered, docs written.
  Decisions: native Swift/AppKit, SPM build (project-local, no PATH
  changes), Cmd+C copies whole canvas, full tool set in v1, PNG save.
- **2026-07-18** — v1 implemented (~900 lines Swift, 260 KB app). Builds
  clean, launches and runs. Awaiting hands-on testing of the full
  paste → mark up → copy round trip.
- **2026-07-18** — Round trip confirmed working by Lee. Added: zoom
  control in bottom-right corner (25%–800%, Cmd+= / Cmd+− / Cmd+0,
  pinch-to-zoom; display-only, output stays full resolution) and a
  visual per-tool width picker (five thicknesses, replaces the S/M/L
  control; each tool remembers its selection).
- **2026-07-18** — Zoom percentage made an editable field (type an exact
  level, Enter commits, Esc reverts). Added Tools menu: Resize Image…
  (⌥⌘R, Preview-style pixels/percent dialog), Rotate Left ⌘L / Right ⌘R,
  Flip Horizontal / Vertical. Transform math verified with a pixel-level
  test. These operations flatten markup into the image.
- **2026-07-18** — Resize dialog defaults to percent at 100%. Added
  Select tool (dashed rectangle, first in palette): Cmd+C copies just
  the selection when active, Tools ▸ Crop to Selection (⌘K) crops to it,
  Esc / tool switch clears it. Crop coordinate mapping verified with a
  pixel-level test.
- **2026-07-18** — Added Tools ▸ Remove Background (⇧⌘K) via Apple
  Vision subject lifting (same engine as Preview; on-device). Background
  becomes true transparency — checkerboard in the view, transparent PNG
  on copy/save — and the operation is undoable. Pipeline verified with a
  synthetic-image test (subject alpha 255, background alpha 0).
- **2026-07-18** — Crop reworked to Preview-style interactive mode:
  ⌘K shows a crop frame with 8 drag handles + dimmed surround; drag to
  frame the keep-area, Return/⌘K applies, Esc cancels. Crop, resize,
  rotate, and flip are now undoable with Cmd+Z (restores prior image,
  size, and live markup strokes).
- **2026-07-18** — Multi-window support: File ▸ New (⌘N) opens extra
  windows (cascaded), each a fully independent document with its own
  markup, undo, tools, and zoom; Close Window (⌘W) confirms before
  discarding markup, and Quit asks once across all windows. Done as an
  extraction refactor first (window code moved from AppDelegate into
  CanvasWindowController; menu actions nil-targeted through the
  responder chain), then the multi-window bookkeeping on top.
  Verified by scripted UI tests: second window opens, paste lands only
  in the frontmost window, per-window close, last-window-close quits,
  discard confirm appears. **Hands-on check still wanted**: the
  Cancel / Discard buttons of the close confirmation.
