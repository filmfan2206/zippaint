import AppKit

@MainActor
final class Document {
    var baseImage: NSImage?
    private(set) var canvasSize = CGSize(width: 800, height: 600)
    private(set) var annotations: [Annotation] = []
    // True after Remove Background: the canvas keeps alpha instead of
    // compositing onto white, so copies/saves are transparent PNGs.
    private(set) var backgroundClear = false

    struct ImageState {
        var image: NSImage?
        var size: CGSize
        var annotations: [Annotation]
        var backgroundClear: Bool
    }

    enum Op {
        case add(Annotation)
        case remove(Int, Annotation)
        case image(before: ImageState, after: ImageState)
    }

    private var undoStack: [Op] = []
    private var redoStack: [Op] = []

    var onChange: (() -> Void)?

    var hasMarkup: Bool { !annotations.isEmpty }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undoStack.append(.add(annotation))
        redoStack.removeAll()
        onChange?()
    }

    func remove(at index: Int) {
        let removed = annotations.remove(at: index)
        undoStack.append(.remove(index, removed))
        redoStack.removeAll()
        onChange?()
    }

    func undo() {
        guard let op = undoStack.popLast() else { NSSound.beep(); return }
        switch op {
        case .add:
            annotations.removeLast()
        case .remove(let index, let annotation):
            annotations.insert(annotation, at: index)
        case .image(let before, _):
            restore(before)
        }
        redoStack.append(op)
        onChange?()
    }

    func redo() {
        guard let op = redoStack.popLast() else { NSSound.beep(); return }
        switch op {
        case .add(let annotation):
            annotations.append(annotation)
        case .remove(let index, _):
            annotations.remove(at: index)
        case .image(_, let after):
            restore(after)
        }
        undoStack.append(op)
        onChange?()
    }

    private func restore(_ state: ImageState) {
        baseImage = state.image
        canvasSize = state.size
        annotations = state.annotations
        backgroundClear = state.backgroundClear
    }

    // New document (paste/open): replaces everything, history cleared.
    func setImage(_ image: NSImage?, size: CGSize) {
        baseImage = image
        canvasSize = size
        annotations.removeAll()
        backgroundClear = false
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }

    // Undoable image operation (crop/resize/rotate/flip/remove background):
    // markup is flattened into the new image, but undo restores it as live
    // strokes. clearBackground nil preserves the current transparency mode.
    func applyImageChange(_ image: NSImage?, size: CGSize, clearBackground: Bool? = nil) {
        let before = ImageState(image: baseImage, size: canvasSize,
                                annotations: annotations, backgroundClear: backgroundClear)
        baseImage = image
        canvasSize = size
        annotations.removeAll()
        if let clearBackground { backgroundClear = clearBackground }
        let after = ImageState(image: image, size: size,
                               annotations: [], backgroundClear: backgroundClear)
        undoStack.append(.image(before: before, after: after))
        redoStack.removeAll()
        onChange?()
    }

    // Draws the full canvas (white background, image, annotations) into the
    // current flipped graphics context. Used by both CanvasView.draw and render().
    func drawContent() {
        if !backgroundClear {
            NSColor.white.setFill()
            CGRect(origin: .zero, size: canvasSize).fill()
        }
        baseImage?.draw(in: CGRect(origin: .zero, size: canvasSize))
        for annotation in annotations { annotation.draw() }
    }

    // Flattens the canvas at 1 point = 1 pixel, so output resolution always
    // matches the source image exactly.
    func render() -> NSBitmapImageRep? {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(data: nil, width: width, height: height,
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: colorSpace,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)
        drawContent()
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgContext.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = canvasSize
        return rep
    }
}
