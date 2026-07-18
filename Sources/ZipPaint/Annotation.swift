import AppKit

enum Tool: CaseIterable {
    case select, pencil, highlighter, eraser, line, rect, arrow, text

    var label: String {
        switch self {
        case .select: return "Select"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "rectangle.dashed"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }
}

extension Tool {
    // Five selectable widths shown in the width picker. The value's meaning
    // depends on the tool: stroke width in px, eraser diameter, or text
    // point size.
    var widthOptions: [CGFloat] {
        switch self {
        case .select: return []
        case .pencil, .line, .rect, .arrow: return [1, 2, 4, 6, 8]
        case .highlighter: return [8, 12, 16, 22, 30]
        case .eraser: return [8, 12, 16, 24, 32]
        case .text: return [12, 16, 22, 28, 36]
        }
    }
}

struct Annotation {
    enum Kind {
        case stroke(points: [CGPoint], highlighter: Bool)
        case line(from: CGPoint, to: CGPoint)
        case rect(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        case text(String, origin: CGPoint, fontSize: CGFloat)
    }

    var kind: Kind
    var color: NSColor
    var width: CGFloat

    // Draws into the current (flipped) NSGraphicsContext.
    func draw() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch kind {
        case .stroke(let points, let highlighter):
            guard let first = points.first else { return }
            if highlighter {
                // Alpha + multiply are applied when the transparency layer is
                // composited, so overlapping segments of one stroke don't
                // double-darken.
                ctx.setAlpha(0.4)
                ctx.setBlendMode(.multiply)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            if points.count == 1 {
                ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2,
                                           width: width, height: width))
            } else {
                ctx.move(to: first)
                for p in points.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
            }
            if highlighter { ctx.endTransparencyLayer() }

        case .line(let from, let to):
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()

        case .rect(let r):
            ctx.stroke(r)

        case .arrow(let from, let to):
            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(12, width * 3.5)
            // Stop the shaft short of the tip so it doesn't poke past the head.
            let shaftEnd = CGPoint(x: to.x - cos(angle) * headLength * 0.6,
                                   y: to.y - sin(angle) * headLength * 0.6)
            ctx.move(to: from)
            ctx.addLine(to: shaftEnd)
            ctx.strokePath()
            let barb1 = CGPoint(x: to.x - cos(angle - 0.45) * headLength,
                                y: to.y - sin(angle - 0.45) * headLength)
            let barb2 = CGPoint(x: to.x - cos(angle + 0.45) * headLength,
                                y: to.y - sin(angle + 0.45) * headLength)
            ctx.move(to: to)
            ctx.addLine(to: barb1)
            ctx.addLine(to: barb2)
            ctx.closePath()
            ctx.fillPath()

        case .text(let string, let origin, let fontSize):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: color,
            ]
            (string as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    func hitTest(_ p: CGPoint, radius: CGFloat) -> Bool {
        let pad = max(width / 2, 3) + radius
        switch kind {
        case .stroke(let points, _):
            guard let first = points.first else { return false }
            if points.count == 1 { return distance(p, first) <= pad }
            for i in 0..<(points.count - 1) {
                if distanceToSegment(p, points[i], points[i + 1]) <= pad { return true }
            }
            return false
        case .line(let a, let b), .arrow(let a, let b):
            return distanceToSegment(p, a, b) <= pad
        case .rect(let r):
            let outer = r.insetBy(dx: -pad, dy: -pad)
            let inner = r.insetBy(dx: pad, dy: pad)
            let insideHole = inner.width > 0 && inner.height > 0 && inner.contains(p)
            return outer.contains(p) && !insideHole
        case .text(let string, let origin, let fontSize):
            let size = (string as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
            ])
            return CGRect(origin: origin, size: size).insetBy(dx: -4, dy: -4).contains(p)
        }
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 { return distance(p, a) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
    t = max(0, min(1, t))
    return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
}
