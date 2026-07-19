# ZipPaint — Architecture

How the app is built. Companion to [SPEC.md](SPEC.md) (what it does).

## Stack

- **Language**: Swift 6
- **UI framework**: AppKit (programmatic, no storyboards/xibs). AppKit is
  chosen over SwiftUI because a paint canvas is fundamentally an
  `NSView` with mouse tracking and custom drawing — AppKit does this
  directly with less code and fewer workarounds.
- **Build**: Swift Package Manager. `swift build` produces the executable;
  `build.sh` wraps it into a standard `ZipPaint.app` bundle with an
  `Info.plist`. No Xcode project file needed.

## Environment policy

Everything is project-local:

- Build artifacts: `<project>/.build/` (SPM default)
- App bundle output: `<project>/ZipPaint.app`
- No PATH changes, no shell-profile edits, no global package installs.
- Configuration (bundle id, app name, deployment target) lives in
  `Package.swift` and variables at the top of `build.sh`.

## Source layout

```
zippaint/
├── Package.swift            # SPM manifest (single executable target)
├── build.sh                 # swift build + assemble ZipPaint.app
├── Sources/ZipPaint/
│   ├── main.swift           # NSApplication bootstrap
│   ├── AppDelegate.swift    # menu bar, app lifecycle, window bookkeeping
│   ├── CanvasWindowController.swift # one canvas window: document + chrome + actions
│   ├── Document.swift       # model: base image + annotation list + undo
│   ├── Annotation.swift     # stroke/shape/text value types
│   ├── CanvasView.swift     # NSView: drawing, mouse tracking, flattening
│   ├── ToolPaletteView.swift# left-side tool buttons + width picker
│   ├── ColorBarView.swift   # bottom palette + current-color well
│   ├── ResizeDialog.swift   # Preview-style "Image Dimensions" dialog
│   └── Clipboard.swift      # NSPasteboard read (paste) / write (copy)
└── *.md                     # project docs
```

Target: roughly 1,000–1,500 lines of Swift total. If a file wants to grow
past ~300 lines, the feature is probably too big for this app.

## Model

The document is deliberately simple — **an image plus an ordered list of
annotations**:

```swift
struct Document {
    var baseImage: NSImage?          // nil = blank white canvas
    var canvasSize: CGSize           // == image pixel size when image present
    var annotations: [Annotation]    // draw order = array order
}

enum Annotation {
    case stroke(points: [CGPoint], color: NSColor, width: CGFloat, highlighter: Bool)
    case line(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat)
    case rect(CGRect, color: NSColor, width: CGFloat)
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat)
    case text(String, at: CGPoint, color: NSColor, size: CGFloat)
}
```

Key consequences of this design:

- **The base image is never mutated.** Rendering always draws the image,
  then the annotations on top. This makes the eraser trivial (delete
  annotations) and guarantees markup never degrades the photo.
- **Undo/redo is an index into history.** Undo pops the last annotation
  onto a redo stack; no snapshots or image diffs needed.
- **Flattening is one render.** Copy and Save both call the same
  `render()` that draws everything into an offscreen bitmap at the
  image's true pixel resolution.

## Key techniques

### Canvas drawing (`CanvasView`)

- `draw(_:)` paints: white background → base image → each annotation →
  the in-progress annotation (while the mouse is down).
- Mouse tracking: `mouseDown` starts an annotation, `mouseDragged`
  extends it (for strokes, appending points; for shapes, updating the
  endpoint), `mouseUp` commits it to the document and registers undo.
- Freehand strokes are rendered as an `NSBezierPath` through the sampled
  points with round caps/joins — smooth enough without curve fitting.

### Highlighter blending

Highlighter strokes draw with `CGBlendMode.multiply` at partial alpha,
so dark image content stays visible through the ink — matching how a
physical highlighter behaves. Overlapping passes of the same stroke are
prevented from double-darkening by drawing each stroke into its own
transparency layer.

### Retina / resolution correctness

The canvas view works in **image pixel coordinates**. A pasted Retina
screenshot keeps its full pixel dimensions; the view scales down for
display if the window is smaller (scrollbars past screen size), but
`render()` always outputs at 1 canvas point = 1 image pixel. This is what
prevents the classic "copied screenshot comes out blurry or double-sized"
bug.

### Clipboard (`Clipboard.swift`)

- **Paste**: `NSPasteboard.general` → `NSImage(pasteboard:)`, then read
  the bitmap rep's `pixelsWide/High` for the true canvas size.
- **Copy**: flatten via `render()`, then write **both** PNG data and TIFF
  data to the pasteboard in one `declareTypes` call. Web browsers prefer
  PNG; Mail and native apps often take TIFF — providing both makes
  paste work everywhere.

### Window sizing on paste

On paste/open, the window's content size is set to the canvas size plus
tool/color chrome, clamped to `NSScreen.visibleFrame`. Oversized images
sit in an `NSScrollView`.

### Text tool

A borderless `NSTextField` is placed at the click point; on Enter/Esc or
focus loss its string is committed as a `.text` annotation and the field
is removed. This avoids implementing a text editor inside the canvas.

### Multiple windows

Each window is a `CanvasWindowController` (an `NSWindowController`
subclass) owning its own `Document`, canvas, tool palette, color bar,
and zoom — there is no shared state between windows. Menu items carry
**no target**, so their actions resolve through the responder chain to
the key window's controller; that is the entire routing mechanism.
`AppDelegate` shrinks to menu construction plus bookkeeping: an array of
live controllers (pruned via an `onWindowClose` callback), cascading new
windows, and the quit-time check across all windows. The controller's
model property is named `doc` because `NSWindowController` already
declares `document`.

## Menu bar

Built programmatically in `AppDelegate`:

- **File**: New (Cmd+N), Open… (Cmd+O), Close Window (Cmd+W),
  Save As PNG… (Cmd+S)
- **Edit**: Undo (Cmd+Z), Redo (Shift+Cmd+Z), Copy (Cmd+C), Paste (Cmd+V)
- Standard App and Window menus.

## Build and packaging (`build.sh`)

1. `swift build -c release`
2. Create `ZipPaint.app/Contents/{MacOS,Resources}`
3. Copy the built binary and a generated `Info.plist` (bundle id
   `local.zippaint`, `NSHighResolutionCapable = true`)
4. Ad-hoc codesign (`codesign -s -`) so macOS runs it without warnings

Result: a double-clickable app ~1 MB in size, entirely inside the
project folder.
