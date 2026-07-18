import AppKit

@MainActor
final class CanvasView: NSView {
    let document: Document

    var tool: Tool = .pencil {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var color: NSColor = .black

    // Active rectangular selection (canvas coordinates), used for
    // copy-selection and crop. View-only overlay — never rendered to output.
    private(set) var selection: CGRect?
    var onSelectionChange: (() -> Void)?

    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        needsDisplay = true
        onSelectionChange?()
    }

    // Crop mode: while cropRect is non-nil, the canvas shows a crop frame
    // with drag handles and consumes all mouse input.
    enum CropHandle {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight, move
    }

    private(set) var cropRect: CGRect?
    var onCropChange: (() -> Void)?
    var onCropCommit: (() -> Void)?
    private var activeCropHandle: CropHandle?
    private var cropMoveOffset = CGPoint.zero

    // Canvas points per screen point, so handles stay grabbable at any zoom.
    private var displayScale: CGFloat {
        max(enclosingScrollView?.magnification ?? 1, 0.01)
    }

    func beginCrop(initial: CGRect) {
        cropRect = initial.intersection(bounds)
        activeCropHandle = nil
        needsDisplay = true
        onCropChange?()
    }

    func cancelCrop() {
        guard cropRect != nil else { return }
        cropRect = nil
        activeCropHandle = nil
        needsDisplay = true
        onCropChange?()
    }

    private func cropHandlePoints(_ r: CGRect) -> [(CropHandle, CGPoint)] {
        [(.topLeft, CGPoint(x: r.minX, y: r.minY)),
         (.top, CGPoint(x: r.midX, y: r.minY)),
         (.topRight, CGPoint(x: r.maxX, y: r.minY)),
         (.left, CGPoint(x: r.minX, y: r.midY)),
         (.right, CGPoint(x: r.maxX, y: r.midY)),
         (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
         (.bottom, CGPoint(x: r.midX, y: r.maxY)),
         (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))]
    }

    // Selected width option per tool, remembered across tool switches.
    private var widthIndices: [Tool: Int] = [
        .pencil: 1, .highlighter: 2, .eraser: 2,
        .line: 1, .rect: 1, .arrow: 1, .text: 1,
    ]

    private var currentAnnotation: Annotation?
    private var dragStart: CGPoint = .zero
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textFontSize: CGFloat = 16

    func widthIndex(for tool: Tool) -> Int {
        widthIndices[tool] ?? 1
    }

    func setWidthIndex(_ index: Int, for tool: Tool) {
        widthIndices[tool] = max(0, min(tool.widthOptions.count - 1, index))
    }

    private func currentValue(for tool: Tool) -> CGFloat {
        let options = tool.widthOptions
        guard !options.isEmpty else { return 1 }
        return options[min(widthIndex(for: tool), options.count - 1)]
    }

    init(document: Document) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.canvasSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if cropRect != nil {
            cancelCrop()
        } else {
            clearSelection()
        }
    }

    override func keyDown(with event: NSEvent) {
        // Return / keypad Enter applies the pending crop.
        if cropRect != nil, event.keyCode == 36 || event.keyCode == 76 {
            onCropCommit?()
            return
        }
        super.keyDown(with: event)
    }

    // Checkerboard shown behind transparent canvases (view only — copies
    // and saves keep real alpha).
    private static let checkerboard: NSColor = {
        let tile = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 16, height: 16).fill()
            NSColor(white: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: tile)
    }()

    override func draw(_ dirtyRect: NSRect) {
        if document.backgroundClear {
            Self.checkerboard.setFill()
            bounds.fill()
        }
        document.drawContent()
        currentAnnotation?.draw()
        if let sel = selection {
            drawMarquee(sel)
        }
        if let crop = cropRect {
            // Dim everything outside the crop frame.
            let dim = NSBezierPath(rect: bounds)
            dim.appendRect(crop)
            dim.windingRule = .evenOdd
            NSColor(calibratedWhite: 0, alpha: 0.45).setFill()
            dim.fill()
            drawMarquee(crop)
            // Drag handles: white squares with black borders.
            let side = 8 / displayScale
            for (_, point) in cropHandlePoints(crop) {
                let handleRect = CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                        width: side, height: side)
                NSColor.white.setFill()
                NSBezierPath(rect: handleRect).fill()
                NSColor.black.setStroke()
                NSBezierPath(rect: handleRect).stroke()
            }
        }
    }

    // White underlay + black dashes stays visible on any image.
    private func drawMarquee(_ rect: CGRect) {
        let solid = NSBezierPath(rect: rect)
        solid.lineWidth = 1
        NSColor.white.setStroke()
        solid.stroke()
        let dashed = NSBezierPath(rect: rect)
        dashed.lineWidth = 1
        var pattern: [CGFloat] = [4, 4]
        dashed.setLineDash(&pattern, count: 2, phase: 0)
        NSColor.black.setStroke()
        dashed.stroke()
    }

    // MARK: - Mouse

    private func canvasPoint(from event: NSEvent) -> CGPoint {
        var p = convert(event.locationInWindow, from: nil)
        p.x = max(0, min(bounds.width, p.x))
        p.y = max(0, min(bounds.height, p.y))
        return p
    }

    override func mouseDown(with event: NSEvent) {
        let p = canvasPoint(from: event)
        commitTextEntry()

        if let crop = cropRect {
            let tolerance = 12 / displayScale
            let candidates = cropHandlePoints(crop)
                .filter { hypot($0.1.x - p.x, $0.1.y - p.y) <= tolerance }
            if let nearest = candidates.min(by: {
                hypot($0.1.x - p.x, $0.1.y - p.y) < hypot($1.1.x - p.x, $1.1.y - p.y)
            }) {
                activeCropHandle = nearest.0
            } else if crop.contains(p) {
                activeCropHandle = .move
                cropMoveOffset = CGPoint(x: p.x - crop.minX, y: p.y - crop.minY)
            } else {
                activeCropHandle = nil
            }
            return
        }

        let width = currentValue(for: tool)

        switch tool {
        case .select:
            dragStart = p
            clearSelection()
        case .pencil, .highlighter:
            currentAnnotation = Annotation(
                kind: .stroke(points: [p], highlighter: tool == .highlighter),
                color: color, width: width)
        case .line:
            dragStart = p
            currentAnnotation = Annotation(kind: .line(from: p, to: p), color: color, width: width)
        case .rect:
            dragStart = p
            currentAnnotation = Annotation(kind: .rect(CGRect(origin: p, size: .zero)),
                                           color: color, width: width)
        case .arrow:
            dragStart = p
            currentAnnotation = Annotation(kind: .arrow(from: p, to: p), color: color, width: width)
        case .eraser:
            erase(at: p)
        case .text:
            beginTextEntry(at: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = canvasPoint(from: event)

        if let crop = cropRect {
            guard let handle = activeCropHandle else { return }
            cropRect = adjustedCrop(crop, handle: handle, to: p)
            needsDisplay = true
            onCropChange?()
            return
        }

        switch tool {
        case .select:
            selection = normalizedRect(dragStart, p)
            onSelectionChange?()
        case .pencil, .highlighter:
            if case .stroke(var points, let highlighter) = currentAnnotation?.kind {
                points.append(p)
                currentAnnotation?.kind = .stroke(points: points, highlighter: highlighter)
            }
        case .line:
            currentAnnotation?.kind = .line(from: dragStart, to: p)
        case .rect:
            currentAnnotation?.kind = .rect(normalizedRect(dragStart, p))
        case .arrow:
            currentAnnotation?.kind = .arrow(from: dragStart, to: p)
        case .eraser:
            erase(at: p)
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if cropRect != nil {
            activeCropHandle = nil
            return
        }
        if tool == .select {
            if let sel = selection, sel.width < 2 || sel.height < 2 {
                clearSelection()
            }
            return
        }
        guard let annotation = currentAnnotation else { return }
        currentAnnotation = nil
        let p = canvasPoint(from: event)

        // Discard shape drags too small to be intentional.
        switch tool {
        case .line, .rect, .arrow:
            if hypot(p.x - dragStart.x, p.y - dragStart.y) < 3 {
                needsDisplay = true
                return
            }
        default:
            break
        }
        document.add(annotation)
        needsDisplay = true
    }

    private func adjustedCrop(_ rect: CGRect, handle: CropHandle, to p: CGPoint) -> CGRect {
        let minSize: CGFloat = 10
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .move:
            var origin = CGPoint(x: p.x - cropMoveOffset.x, y: p.y - cropMoveOffset.y)
            origin.x = max(0, min(bounds.width - rect.width, origin.x))
            origin.y = max(0, min(bounds.height - rect.height, origin.y))
            return CGRect(origin: origin, size: rect.size)
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .left: minX = p.x
        case .right: maxX = p.x
        case .bottomLeft: minX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomRight: maxX = p.x; maxY = p.y
        }
        minX = max(0, min(minX, maxX - minSize))
        minY = max(0, min(minY, maxY - minSize))
        maxX = min(bounds.width, max(maxX, minX + minSize))
        maxY = min(bounds.height, max(maxY, minY + minSize))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func erase(at p: CGPoint) {
        let radius = currentValue(for: .eraser) / 2
        for index in document.annotations.indices.reversed()
        where document.annotations[index].hitTest(p, radius: radius) {
            document.remove(at: index)
            needsDisplay = true
            return
        }
    }

    // MARK: - Text entry

    private func beginTextEntry(at p: CGPoint) {
        let fontSize = currentValue(for: .text)
        textFontSize = fontSize
        let field = NSTextField(frame: CGRect(x: p.x, y: p.y, width: 180, height: fontSize + 10))
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = color
        field.backgroundColor = NSColor.white.withAlphaComponent(0.7)
        field.isBordered = true
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOrigin = p
    }

    func commitTextEntry() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        if !string.isEmpty {
            document.add(Annotation(
                kind: .text(string, origin: textOrigin, fontSize: textFontSize),
                color: color, width: 1))
        }
        needsDisplay = true
    }
}

extension CanvasView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEntry()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitTextEntry()
            return true
        }
        return false
    }
}

// Anchors the canvas to the top-left of the scroll area, like MS Paint,
// instead of AppKit's default bottom-left.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
