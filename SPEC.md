# ZipPaint — Specification

The requirements and decisions for v1. If a behavior isn't described here,
it's out of scope — the guiding principle is **light and small**.

## Goal

A minimal, native macOS markup tool modeled on the feel of classic Windows
Paint. The primary loop is: paste an image, annotate it, copy the annotated
result back to the clipboard for pasting into chats, email, or documents.

## Decisions made

| Decision | Choice |
|---|---|
| Platform | Native macOS app, Swift 6, AppKit |
| Build system | Swift Package Manager (project-local `.build/`, no system changes) |
| Copy behavior | **Cmd+C copies the entire canvas**; with an active selection, just that region |
| Tools | Pencil, Highlighter, Eraser, Line, Rectangle, Arrow, Text |
| File support | Save as PNG (Cmd+S) and Open image (Cmd+O), in addition to clipboard |
| Canvas sizing | Auto-adjusts to the size of the pasted/opened image |
| Distribution | Built and run locally; no App Store, no code-signing requirements |

## Functional requirements

### Canvas and images

- **Paste (Cmd+V)**: replaces the canvas contents with the clipboard image.
  The canvas resizes to the image's exact pixel dimensions. The window
  resizes to fit the canvas, capped at the visible screen area (larger
  images get scrollbars).
  - If there is unsaved markup, ask before replacing.
  - If the clipboard has no image, do nothing (or beep).
- **Open (Cmd+O)**: same as paste, but from a PNG/JPEG/TIFF/HEIC file.
- **Blank start**: on launch, show a default white canvas (800×600) so the
  app is usable even without pasting.
- **Retina**: pasted images keep their true pixel dimensions; copy/save
  output matches the source resolution (no accidental 2× scaling).

### Tools

All tools draw **on top of** the image. The original image is never
modified until the canvas is flattened for copy/save.

- **Select**: drag out a dashed rectangle. While a selection is active,
  Cmd+C copies just that region (flattened, full resolution) and
  Tools ▸ Crop to Selection (⌘K) crops the canvas to it. Esc, switching
  tools, or starting a new drag clears it. The selection marquee never
  appears in copied/saved output. Selection does not move pixels
  (deliberately — this is a markup tool, not an editor).

- **Pencil**: opaque freehand stroke. Widths: 2 / 4 / 8 px.
- **Highlighter**: wide semi-transparent stroke (~40% opacity, multiply-style
  blending so the image shows through, like a real highlighter). Widths:
  12 / 20 / 28 px.
- **Eraser**: removes markup strokes it touches, revealing the original
  image. It never erases the image itself. (Implementation: whole-stroke
  deletion on contact — simplest and predictable with undo.)
- **Line**: drag from start to end; straight line in current color/width.
- **Rectangle**: drag to define; outline only (no fill) in v1.
- **Arrow**: drag from tail to head; solid head triangle sized to stroke width.
- **Text**: click to place a text cursor, type a label, click elsewhere or
  press Esc/Enter to commit. One font (system), size tied to stroke-width
  setting (small/medium/large).

### Color and width

- MS-Paint-style palette: 2 rows of common colors (black, white, grays,
  red, orange, yellow, green, blue, purple, pink, brown — ~16 swatches).
- Current color shown in an indicator well.
- **Width picker**: an MS-Paint-style box below the tools showing five
  selectable widths drawn as actual line thicknesses. The options adapt
  to the active tool (pencil/shapes 1–8 px, highlighter 8–30 px, eraser
  diameter, text point size), and each tool remembers its own selection.

### Zoom

- Zoom control (− / percentage / +) in the bottom-right corner of the
  window, plus View menu items: Zoom In (Cmd+=), Zoom Out (Cmd+−),
  Actual Size (Cmd+0). Trackpad pinch also works.
- The percentage is an editable field: click it, type any value
  (e.g. "130" or "130%"), press Enter to zoom to exactly that. Esc
  reverts; invalid input is ignored. The − / + buttons step to the next
  preset level from wherever you are.
- Range: 25% – 800%.
- Zoom is **display only** — Copy and Save always output at the image's
  full resolution. Pasting a new image resets zoom to 100%.

### Tools menu (image operations)

Modeled on Preview. All of these operate on the **flattened** canvas: any
markup is baked into the image first (visually identical; Cmd+Z undoes
the whole operation and restores the markup as live strokes).

- **Resize Image… (⌥⌘R)**: Preview-style dialog — width/height fields,
  pixels or percent units (percent is the default, opening at 100%),
  "Scale proportionally" checkbox, live "Resulting size" readout. Clamped to 1–20,000 px. (No DPI setting —
  meaningless for clipboard images.)
- **Crop Image (⌘K)**: enters crop mode — the canvas shows a crop frame
  with 8 drag handles (corners + edge midpoints) and dims everything
  outside it. Drag handles to resize, drag inside the frame to move it.
  Return (or ⌘K again) applies the crop; Esc cancels. If a selection is
  active when entering crop mode, it seeds the initial frame; otherwise
  the frame starts at the full image.
- **Remove Background (⇧⌘K)**: keeps the auto-detected subject and makes
  everything else transparent, using the same Apple Vision engine as
  Preview (macOS 14+, on-device, no network). Transparency shows as a
  checkerboard in the canvas (display only); Cmd+C / Cmd+S output
  transparent PNGs. Undoable.
- **Rotate Left (⌘L)** / **Rotate Right (⌘R)**: 90° rotation; canvas
  dimensions swap and the window refits.
- **Flip Horizontal** / **Flip Vertical**: mirror the canvas.

### Undo / Redo

- Cmd+Z (Edit ▸ Undo) undoes the last committed stroke/shape/text **or**
  image operation (crop, resize, rotate, flip); Shift+Cmd+Z redoes.
- Undoing an image operation restores the previous image, canvas size,
  and any markup as live, individually-erasable strokes.
- Unlimited depth within the session. Pasting/opening a new image clears
  history (it starts a new document).

### Output

- **Copy (Cmd+C)**: flattens image + all markup at full resolution and
  places it on the clipboard as PNG **and** TIFF (so every target app —
  web chats, Mail, Office — finds a format it likes).
- **Save (Cmd+S)**: same flattened result written as a PNG file via the
  standard save dialog.

## UI layout (modeled on the reference MS Paint screenshot)

```
+--------------------------------------------------+
| ZipPaint                     [standard traffic lights]
+------+-------------------------------------------+
| Tool |                                           |
| pal- |                                           |
| ette |            Canvas (scrollable)            |
| 2-col|                                           |
| grid |                                           |
|      |                                           |
| width|                                           |
+------+-------------------------------------------+
| [current color] [16-swatch color palette]        |
+--------------------------------------------------+
| Status bar: tool hint / image size               |
+--------------------------------------------------+
```

- Tool palette: vertical 2-column icon grid on the left (like MS Paint).
- Color bar across the bottom with the current-color well at the left.
- Standard macOS menu bar: File (Open, Save), Edit (Undo, Redo, Cut n/a,
  Copy, Paste), with the usual shortcuts.

## Non-goals (v1)

- No moving/dragging selected pixels (selection is for copy/crop only).
- No fill/bucket, spray, or curve tools.
- No multiple documents, tabs, or windows.
- No preferences window.
- No modification of the underlying image pixels (markup is an overlay).

## Environment constraints

- **Nothing outside the project folder.** No PATH edits, no shell-profile
  changes, no globally installed tools. Building uses the system's existing
  Swift toolchain; all artifacts go to `.build/` and `ZipPaint.app` inside
  the project directory.
- Any tweakable build/run settings live in project-local files (e.g.
  `build.sh` variables), never in exported environment variables.
