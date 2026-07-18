import AppKit

// MS-Paint-style width box: one row per selectable width, drawn as an
// actual line of that thickness. Click a row to select it.
@MainActor
final class WidthPickerView: NSView {
    var onSelect: ((Int) -> Void)?

    private var widths: [CGFloat] = []
    private var selectedIndex = 0
    private let rowHeight: CGFloat = 16
    private let boxWidth: CGFloat = 64

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: boxWidth, height: rowHeight * CGFloat(widths.count))
    }

    func show(widths: [CGFloat], selectedIndex: Int) {
        self.widths = widths
        self.selectedIndex = max(0, min(widths.count - 1, selectedIndex))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        for (index, width) in widths.enumerated() {
            let row = NSRect(x: 0, y: CGFloat(index) * rowHeight,
                             width: bounds.width, height: rowHeight)
            if index == selectedIndex {
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                row.fill()
            }
            // Cap the drawn thickness so big widths still fit the row.
            let thickness = min(width, rowHeight - 4)
            let line = NSRect(x: 8, y: row.midY - thickness / 2,
                              width: bounds.width - 16, height: thickness)
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: line, xRadius: thickness / 2,
                         yRadius: thickness / 2).fill()
        }
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let index = Int(p.y / rowHeight)
        guard widths.indices.contains(index) else { return }
        selectedIndex = index
        needsDisplay = true
        onSelect?(index)
    }
}

@MainActor
final class ToolPaletteView: NSView {
    var onToolChange: ((Tool) -> Void)?
    var onWidthSelect: ((Int) -> Void)?

    private var buttons: [(tool: Tool, button: NSButton)] = []
    private let widthPicker = WidthPickerView()

    init() {
        super.init(frame: .zero)

        var rows: [[NSView]] = []
        var currentRow: [NSView] = []
        for tool in Tool.allCases {
            let button = NSButton(title: "", target: self, action: #selector(toolClicked(_:)))
            if let image = NSImage(systemSymbolName: tool.symbolName,
                                   accessibilityDescription: tool.label) {
                button.image = image
            } else {
                button.title = String(tool.label.prefix(1))
            }
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .regularSquare
            button.toolTip = tool.label
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            buttons.append((tool, button))
            currentRow.append(button)
            if currentRow.count == 2 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 4
        grid.translatesAutoresizingMaskIntoConstraints = false

        widthPicker.toolTip = "Stroke width"
        widthPicker.onSelect = { [weak self] index in self?.onWidthSelect?(index) }
        widthPicker.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [grid, widthPicker])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        select(tool: .pencil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func select(tool: Tool) {
        for (t, button) in buttons {
            button.state = (t == tool) ? .on : .off
            button.contentTintColor = (t == tool) ? .controlAccentColor : .labelColor
        }
    }

    func showWidths(_ widths: [CGFloat], selectedIndex: Int) {
        widthPicker.show(widths: widths, selectedIndex: selectedIndex)
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard let entry = buttons.first(where: { $0.button == sender }) else { return }
        select(tool: entry.tool)
        onToolChange?(entry.tool)
    }
}
