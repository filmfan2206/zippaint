import AppKit

@MainActor
final class ColorBarView: NSView {
    var onColorChange: ((NSColor) -> Void)?

    static let colors: [NSColor] = [
        NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1),  // black
        NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1),  // dark gray
        NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),  // light gray
        NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),  // white
        NSColor(red: 0.60, green: 0.10, blue: 0.10, alpha: 1),  // dark red
        NSColor(red: 0.93, green: 0.11, blue: 0.14, alpha: 1),  // red
        NSColor(red: 1.00, green: 0.50, blue: 0.00, alpha: 1),  // orange
        NSColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1),  // yellow
        NSColor(red: 0.00, green: 0.60, blue: 0.20, alpha: 1),  // green
        NSColor(red: 0.45, green: 0.85, blue: 0.35, alpha: 1),  // light green
        NSColor(red: 0.00, green: 0.75, blue: 0.85, alpha: 1),  // cyan
        NSColor(red: 0.00, green: 0.30, blue: 0.90, alpha: 1),  // blue
        NSColor(red: 0.15, green: 0.10, blue: 0.55, alpha: 1),  // navy
        NSColor(red: 0.55, green: 0.15, blue: 0.75, alpha: 1),  // purple
        NSColor(red: 1.00, green: 0.35, blue: 0.70, alpha: 1),  // pink
        NSColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1),  // brown
    ]

    private let well = NSView()

    init() {
        super.init(frame: .zero)

        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor.black.cgColor
        well.layer?.borderColor = NSColor.separatorColor.cgColor
        well.layer?.borderWidth = 1
        well.layer?.cornerRadius = 3
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 34).isActive = true
        well.heightAnchor.constraint(equalToConstant: 34).isActive = true
        well.toolTip = "Current color"

        var rows: [NSStackView] = []
        for rowIndex in 0..<2 {
            var swatches: [NSView] = []
            for column in 0..<8 {
                let index = rowIndex * 8 + column
                let swatch = NSButton(title: "", target: self, action: #selector(swatchClicked(_:)))
                swatch.tag = index
                swatch.isBordered = false
                swatch.wantsLayer = true
                swatch.layer?.backgroundColor = Self.colors[index].cgColor
                swatch.layer?.borderColor = NSColor.separatorColor.cgColor
                swatch.layer?.borderWidth = 1
                swatch.layer?.cornerRadius = 2
                swatch.translatesAutoresizingMaskIntoConstraints = false
                swatch.widthAnchor.constraint(equalToConstant: 20).isActive = true
                swatch.heightAnchor.constraint(equalToConstant: 15).isActive = true
                swatches.append(swatch)
            }
            let row = NSStackView(views: swatches)
            row.orientation = .horizontal
            row.spacing = 3
            rows.append(row)
        }
        let swatchColumn = NSStackView(views: rows)
        swatchColumn.orientation = .vertical
        swatchColumn.spacing = 3

        let stack = NSStackView(views: [well, swatchColumn])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setCurrent(_ color: NSColor) {
        well.layer?.backgroundColor = color.cgColor
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        let color = Self.colors[sender.tag]
        setCurrent(color)
        onColorChange?(color)
    }
}
