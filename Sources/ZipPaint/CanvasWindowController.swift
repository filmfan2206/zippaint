import AppKit
import UniformTypeIdentifiers
import Vision

// One canvas window: a Document plus all the chrome around it (tool palette,
// color bar, status bar, zoom). Menu items are nil-targeted, so their actions
// reach the key window's controller through the responder chain.
@MainActor
final class CanvasWindowController: NSWindowController {
    let doc = Document()
    // Lets AppDelegate drop its reference once the window is gone.
    var onWindowClose: (() -> Void)?
    private var canvas: CanvasView!
    private var scroll: NSScrollView!
    private var palette: ToolPaletteView!
    private var colorBar: ColorBarView!
    private var status: NSTextField!
    private var zoomLabel: NSTextField!

    // Space the tool palette / color bar / status bar add around the canvas.
    private let chromeWidth: CGFloat = 96
    private let chromeHeight: CGFloat = 84

    // Display zoom only — copy/save always output at full resolution.
    // The − / + buttons step through these; the editable field accepts any
    // value in between.
    private let zoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "untitled – ZipPaint"
        window.contentMinSize = NSSize(width: 440, height: 400)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        resizeWindowToFitCanvas()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - UI construction

    private func buildContent() -> NSView {
        let content = NSView()

        canvas = CanvasView(document: doc)
        doc.onChange = { [weak self] in
            guard let self else { return }
            // Undo/redo and image operations can change the canvas size;
            // refit the window when they do.
            if self.canvas.frame.size != self.doc.canvasSize {
                self.canvasSizeChanged()
            } else {
                self.canvas.needsDisplay = true
            }
        }

        scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView = FlippedClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.borderType = .noBorder
        scroll.allowsMagnification = true
        scroll.minMagnification = zoomLevels.first!
        scroll.maxMagnification = zoomLevels.last!
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyEnded(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)

        palette = ToolPaletteView()
        palette.translatesAutoresizingMaskIntoConstraints = false
        palette.onToolChange = { [weak self] tool in
            guard let self else { return }
            self.canvas.commitTextEntry()
            self.canvas.clearSelection()
            self.canvas.cancelCrop()
            self.canvas.tool = tool
            // A black highlighter is never what anyone wants.
            if tool == .highlighter, self.canvas.color == ColorBarView.colors[0] {
                self.setColor(ColorBarView.colors[7])
            }
            self.palette.showWidths(tool.widthOptions,
                                    selectedIndex: self.canvas.widthIndex(for: tool))
            self.updateStatus()
        }
        palette.onWidthSelect = { [weak self] index in
            guard let self else { return }
            self.canvas.setWidthIndex(index, for: self.canvas.tool)
        }
        palette.onHalveSize = { [weak self] in self?.halveImageSize() }
        palette.showWidths(Tool.pencil.widthOptions,
                           selectedIndex: canvas.widthIndex(for: .pencil))

        colorBar = ColorBarView()
        colorBar.translatesAutoresizingMaskIntoConstraints = false
        colorBar.onColorChange = { [weak self] color in
            self?.canvas.color = color
        }
        canvas.onSelectionChange = { [weak self] in self?.updateStatus() }
        canvas.onCropChange = { [weak self] in self?.updateStatus() }
        canvas.onCropCommit = { [weak self] in self?.applyCrop() }

        status = NSTextField(labelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail

        let zoomOut = NSButton(title: "−", target: self, action: #selector(zoomOutAction(_:)))
        let zoomIn = NSButton(title: "+", target: self, action: #selector(zoomInAction(_:)))
        for button in [zoomOut, zoomIn] {
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12)
        }
        zoomOut.toolTip = "Zoom out (Cmd −)"
        zoomIn.toolTip = "Zoom in (Cmd =)"
        zoomLabel = NSTextField(string: "100%")
        zoomLabel.isEditable = true
        zoomLabel.isBezeled = true
        zoomLabel.bezelStyle = .roundedBezel
        zoomLabel.controlSize = .small
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.alignment = .center
        zoomLabel.delegate = self
        zoomLabel.toolTip = "Click to type a zoom level (25–800%) — copies and saves are always full resolution"
        let zoomStack = NSStackView(views: [zoomOut, zoomLabel, zoomIn])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 3
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        content.addSubview(palette)
        content.addSubview(scroll)
        content.addSubview(colorBar)
        content.addSubview(status)
        content.addSubview(zoomStack)

        NSLayoutConstraint.activate([
            palette.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            palette.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            palette.widthAnchor.constraint(equalToConstant: 80),
            palette.bottomAnchor.constraint(lessThanOrEqualTo: colorBar.topAnchor),

            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: palette.trailingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            colorBar.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            colorBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            colorBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            colorBar.heightAnchor.constraint(equalToConstant: 56),

            status.topAnchor.constraint(equalTo: colorBar.bottomAnchor, constant: 2),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            status.trailingAnchor.constraint(lessThanOrEqualTo: zoomStack.leadingAnchor, constant: -10),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),

            zoomStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            zoomStack.centerYAnchor.constraint(equalTo: status.centerYAnchor),
        ])

        updateStatus()
        return content
    }

    // MARK: - Actions

    @objc func pasteImage(_ sender: Any?) {
        canvas.commitTextEntry()
        guard let (image, size) = Clipboard.readImage() else {
            NSSound.beep()
            flashStatus("No image on the clipboard")
            return
        }
        if doc.hasMarkup,
           !Self.confirmDiscard("Replace the canvas and discard your current markup?") {
            return
        }
        doc.setImage(image, size: size)
        canvasSizeChanged(displayScale: displayScale(of: image, pixelSize: size))
    }

    @objc func copyCanvas(_ sender: Any?) {
        canvas.commitTextEntry()
        let region = canvas.selection
        if Clipboard.copyFlattened(doc, region: region) {
            if let region {
                flashStatus("Copied selection (\(Int(region.width)) × \(Int(region.height)) px) to clipboard — paste it anywhere")
            } else {
                flashStatus("Copied \(Int(doc.canvasSize.width)) × \(Int(doc.canvasSize.height)) px to clipboard — paste it anywhere")
            }
        } else {
            NSSound.beep()
        }
    }

    // First ⌘K enters crop mode (a selection, if any, seeds the frame);
    // ⌘K again or Return applies it, Esc cancels.
    @objc func cropAction(_ sender: Any?) {
        canvas.commitTextEntry()
        if canvas.cropRect != nil {
            applyCrop()
            return
        }
        let initial = canvas.selection ?? CGRect(origin: .zero, size: doc.canvasSize)
        canvas.clearSelection()
        canvas.beginCrop(initial: initial)
        window?.makeFirstResponder(canvas)
    }

    private func applyCrop() {
        guard let crop = canvas.cropRect else { return }
        let rect = crop.integral.intersection(CGRect(origin: .zero, size: doc.canvasSize))
        guard rect.width >= 1, rect.height >= 1,
              let rep = doc.render(),
              let cgImage = rep.cgImage?.cropping(to: rect)
        else { NSSound.beep(); return }
        canvas.cancelCrop()
        doc.applyImageChange(NSImage(cgImage: cgImage, size: rect.size), size: rect.size)
        flashStatus("Cropped to \(Int(rect.width)) × \(Int(rect.height)) px — Cmd+Z to undo")
    }

    @objc func undo(_ sender: Any?) {
        canvas.commitTextEntry()
        doc.undo()
    }

    @objc func redo(_ sender: Any?) {
        doc.redo()
    }

    @objc func openImage(_ sender: Any?) {
        canvas.commitTextEntry()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        var pixelsWide = 0, pixelsHigh = 0
        for rep in image.representations {
            pixelsWide = max(pixelsWide, rep.pixelsWide)
            pixelsHigh = max(pixelsHigh, rep.pixelsHigh)
        }
        let size = (pixelsWide > 0 && pixelsHigh > 0)
            ? CGSize(width: pixelsWide, height: pixelsHigh)
            : image.size
        if doc.hasMarkup,
           !Self.confirmDiscard("Replace the canvas and discard your current markup?") {
            return
        }
        doc.setImage(image, size: size)
        canvasSizeChanged(displayScale: displayScale(of: image, pixelSize: size))
        window?.title = "\(url.lastPathComponent) – ZipPaint"
    }

    @objc func saveImage(_ sender: Any?) {
        canvas.commitTextEntry()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "markup.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let rep = doc.render(),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
            flashStatus("Saved \(url.lastPathComponent)")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Image transforms

    @objc func resizeImage(_ sender: Any?) {
        canvas.commitTextEntry()
        let dialog = ResizeDialog(originalSize: doc.canvasSize,
                                  hasMarkup: doc.hasMarkup)
        guard let newSize = dialog.run() else { return }
        applyResize(to: newSize)
    }

    // Halve the canvas's pixel dimensions in one click (the palette "50%"
    // button). Each press works off the current size, so repeated presses
    // compound (50% → 25% → …), matching Tools ▸ Resize Image.
    func halveImageSize() {
        canvas.commitTextEntry()
        let newSize = CGSize(width: max(1, (doc.canvasSize.width / 2).rounded()),
                             height: max(1, (doc.canvasSize.height / 2).rounded()))
        guard newSize != doc.canvasSize else { NSSound.beep(); return }
        applyResize(to: newSize)
    }

    // Flatten current markup and redraw into a new canvas size. Undoable.
    private func applyResize(to newSize: CGSize) {
        guard let rep = doc.render() else { NSSound.beep(); return }
        // The flattened image is drawn into the new canvas size by
        // drawContent(), which handles the scaling.
        let image = NSImage()
        image.addRepresentation(rep)
        doc.applyImageChange(image, size: newSize)
        flashStatus("Resized to \(Int(newSize.width)) × \(Int(newSize.height)) px — Cmd+Z to undo")
    }

    @objc func rotateLeft(_ sender: Any?) {
        let h = doc.canvasSize.height
        transformCanvas(newSize: CGSize(width: doc.canvasSize.height,
                                        height: doc.canvasSize.width)) { ctx in
            ctx.translateBy(x: h, y: 0)
            ctx.rotate(by: .pi / 2)
        }
    }

    @objc func rotateRight(_ sender: Any?) {
        let w = doc.canvasSize.width
        transformCanvas(newSize: CGSize(width: doc.canvasSize.height,
                                        height: doc.canvasSize.width)) { ctx in
            ctx.translateBy(x: 0, y: w)
            ctx.rotate(by: -.pi / 2)
        }
    }

    @objc func flipHorizontal(_ sender: Any?) {
        let w = doc.canvasSize.width
        transformCanvas(newSize: doc.canvasSize) { ctx in
            ctx.translateBy(x: w, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
    }

    @objc func flipVertical(_ sender: Any?) {
        let h = doc.canvasSize.height
        transformCanvas(newSize: doc.canvasSize) { ctx in
            ctx.translateBy(x: 0, y: h)
            ctx.scaleBy(x: 1, y: -1)
        }
    }

    // Flattens the canvas (image + markup), then redraws it through the
    // given transform into a new canvas of newSize.
    private func transformCanvas(newSize: CGSize, setup: (CGContext) -> Void) {
        canvas.commitTextEntry()
        let oldSize = doc.canvasSize
        guard let rep = doc.render(),
              let cgImage = rep.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: Int(newSize.width), height: Int(newSize.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { NSSound.beep(); return }
        setup(ctx)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: oldSize))
        guard let output = ctx.makeImage() else { NSSound.beep(); return }
        doc.applyImageChange(NSImage(cgImage: output, size: newSize), size: newSize)
    }

    // Keeps the Vision-detected subject, makes everything else transparent —
    // same engine as Preview's Remove Background.
    @objc func removeBackground(_ sender: Any?) {
        canvas.commitTextEntry()
        canvas.cancelCrop()
        guard #available(macOS 14.0, *) else {
            flashStatus("Remove Background needs macOS 14 or later")
            NSSound.beep()
            return
        }
        status.stringValue = "Removing background…"
        status.display()
        // Let the status repaint before the (possibly slow) Vision request.
        DispatchQueue.main.async { self.performRemoveBackground() }
    }

    @available(macOS 14.0, *)
    private func performRemoveBackground() {
        guard let rep = doc.render(), let cgImage = rep.cgImage else {
            NSSound.beep()
            updateStatus()
            return
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                NSSound.beep()
                flashStatus("No subject found — the image needs a distinct foreground")
                return
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
                NSSound.beep()
                updateStatus()
                return
            }
            doc.applyImageChange(NSImage(cgImage: output, size: doc.canvasSize),
                                      size: doc.canvasSize,
                                      clearBackground: true)
            flashStatus("Background removed — copies are transparent PNGs, Cmd+Z to undo")
        } catch {
            NSSound.beep()
            flashStatus("Background removal failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Zoom

    @objc func zoomInAction(_ sender: Any?) {
        applyMagnification(zoomLevels.first(where: { $0 > scroll.magnification + 0.001 })
                           ?? zoomLevels.last!)
    }

    @objc func zoomOutAction(_ sender: Any?) {
        applyMagnification(zoomLevels.last(where: { $0 < scroll.magnification - 0.001 })
                           ?? zoomLevels.first!)
    }

    @objc func zoomActualAction(_ sender: Any?) { applyMagnification(1) }

    private func applyMagnification(_ requested: CGFloat) {
        let magnification = max(zoomLevels.first!, min(zoomLevels.last!, requested))
        let visible = scroll.contentView.documentVisibleRect
        scroll.setMagnification(magnification,
                                centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        zoomLabel.stringValue = "\(Int((magnification * 100).rounded()))%"
    }

    @objc private func liveMagnifyEnded(_ note: Notification) {
        zoomLabel.stringValue = "\(Int((scroll.magnification * 100).rounded()))%"
    }

    private func commitZoomField() {
        let text = zoomLabel.stringValue
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let value = Double(text), value > 0 {
            applyMagnification(CGFloat(value) / 100)
        } else {
            // Junk input: revert to the actual current zoom.
            zoomLabel.stringValue = "\(Int((scroll.magnification * 100).rounded()))%"
        }
        window?.makeFirstResponder(nil)
    }

    // MARK: - Helpers

    private func setColor(_ color: NSColor) {
        canvas.color = color
        colorBar.setCurrent(color)
    }

    // Pixels per point of the source image: 2 for Retina screenshots, 1 for
    // ordinary images. Zooming to 1/scale shows the canvas at the size the
    // image had on screen (display only — output stays full resolution).
    private func displayScale(of image: NSImage, pixelSize: CGSize) -> CGFloat {
        guard image.size.width > 0 else { return 1 }
        let scale = pixelSize.width / image.size.width
        return scale > 1 ? scale : 1
    }

    private func canvasSizeChanged(displayScale: CGFloat = 1) {
        canvas.clearSelection()
        canvas.cancelCrop()
        canvas.setFrameSize(doc.canvasSize)
        canvas.needsDisplay = true
        applyMagnification(1 / displayScale)
        resizeWindowToFitCanvas(zoom: 1 / displayScale)
        updateStatus()
        window?.title = "untitled – ZipPaint"
    }

    private func resizeWindowToFitCanvas(zoom: CGFloat = 1) {
        guard let window else { return }
        let desired = NSSize(width: doc.canvasSize.width * zoom + chromeWidth,
                             height: doc.canvasSize.height * zoom + chromeHeight)
        let visible = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let target = NSSize(
            width: min(max(desired.width, window.contentMinSize.width), visible.width - 20),
            height: min(max(desired.height, window.contentMinSize.height), visible.height - 40))

        let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(target)
        var frame = window.frame
        frame.origin = CGPoint(x: topLeft.x, y: topLeft.y - frame.height)
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        window.setFrame(frame, display: true)
    }

    private func updateStatus() {
        if let crop = canvas.cropRect {
            status.stringValue = "Crop: \(Int(crop.width)) × \(Int(crop.height)) px   •   drag the handles, then Return (or Cmd+K) to crop — Esc cancels"
            return
        }
        if let sel = canvas.selection {
            status.stringValue = "Selection: \(Int(sel.width)) × \(Int(sel.height)) px   •   Cmd+C copies it, Cmd+K crops to it, Esc clears"
            return
        }
        let w = Int(doc.canvasSize.width)
        let h = Int(doc.canvasSize.height)
        status.stringValue = "\(w) × \(h) px   •   \(canvas.tool.label)   •   Cmd+V paste in, Cmd+C copy out"
    }

    private func flashStatus(_ message: String) {
        status.stringValue = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.updateStatus()
        }
    }

    static func confirmDiscard(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Your markup will be lost. Use Cmd+C or Cmd+S first if you want to keep it."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension CanvasWindowController: NSWindowDelegate {
    // Cmd+W / the close button must not silently discard markup. (Quit goes
    // through applicationShouldTerminate instead, which asks once for all
    // windows and never reaches this.)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !doc.hasMarkup || Self.confirmDiscard("Close this window and discard its markup?")
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        onWindowClose?()
    }
}

extension CanvasWindowController: NSTextFieldDelegate {
    // Zoom field: Enter or clicking away commits; Esc reverts.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === zoomLabel else { return }
        commitZoomField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === zoomLabel else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            zoomLabel.stringValue = "\(Int((scroll.magnification * 100).rounded()))%"
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}
