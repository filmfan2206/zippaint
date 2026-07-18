import AppKit

// Preview-style "Image Dimensions" dialog: width/height in pixels or
// percent, proportional scaling, live resulting-size readout.
@MainActor
final class ResizeDialog: NSObject {
    private enum Unit: Int {
        case pixels = 0, percent
    }

    private let originalSize: CGSize
    private let hasMarkup: Bool
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private let unitPopup = NSPopUpButton()
    private let proportionalCheck = NSButton(checkboxWithTitle: "Scale proportionally",
                                             target: nil, action: nil)
    private let resultLabel = NSTextField(labelWithString: "")
    private var unit: Unit = .percent
    private var syncing = false

    init(originalSize: CGSize, hasMarkup: Bool) {
        self.originalSize = originalSize
        self.hasMarkup = hasMarkup
    }

    // Returns the new pixel size, or nil if cancelled / unchanged / invalid.
    func run() -> CGSize? {
        for field in [widthField, heightField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
            field.alignment = .right
            field.delegate = self
        }
        widthField.stringValue = "100"
        heightField.stringValue = "100"

        unitPopup.addItems(withTitles: ["pixels", "percent"])
        unitPopup.selectItem(at: unit.rawValue)
        unitPopup.target = self
        unitPopup.action = #selector(unitChanged(_:))

        proportionalCheck.state = .on
        proportionalCheck.target = self
        proportionalCheck.action = #selector(proportionalToggled(_:))

        resultLabel.font = .systemFont(ofSize: 11)
        resultLabel.textColor = .secondaryLabelColor
        updateResultLabel()

        let grid = NSGridView(views: [
            [label("Width:"), widthField, unitPopup],
            [label("Height:"), heightField, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, proportionalCheck, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, resultLabel, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.row(at: 2).mergeCells(in: NSRange(location: 1, length: 2))
        grid.row(at: 3).mergeCells(in: NSRange(location: 1, length: 2))
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Image Dimensions"
        if hasMarkup {
            alert.informativeText = "Your markup will be flattened into the resized image."
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid
        alert.window.initialFirstResponder = widthField

        guard alert.runModal() == .alertFirstButtonReturn,
              let size = computedPixelSize(),
              size != originalSize
        else { return nil }
        return size
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private var aspect: CGFloat {
        originalSize.height > 0 ? originalSize.width / originalSize.height : 1
    }

    private func computedPixelSize() -> CGSize? {
        guard let w = Double(widthField.stringValue.trimmingCharacters(in: .whitespaces)),
              let h = Double(heightField.stringValue.trimmingCharacters(in: .whitespaces)),
              w > 0, h > 0
        else { return nil }
        var size: CGSize
        switch unit {
        case .pixels:
            size = CGSize(width: w, height: h)
        case .percent:
            size = CGSize(width: originalSize.width * w / 100,
                          height: originalSize.height * h / 100)
        }
        size = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard (1...20000).contains(size.width), (1...20000).contains(size.height) else {
            return nil
        }
        return size
    }

    private func updateResultLabel() {
        if let size = computedPixelSize() {
            resultLabel.stringValue = "Resulting size: \(Int(size.width)) × \(Int(size.height)) pixels"
        } else {
            resultLabel.stringValue = "Resulting size: —"
        }
    }

    @objc private func unitChanged(_ sender: NSPopUpButton) {
        let newUnit = Unit(rawValue: sender.indexOfSelectedItem) ?? .pixels
        guard newUnit != unit else { return }
        let pixelSize = computedPixelSize()
        unit = newUnit
        syncing = true
        switch (unit, pixelSize) {
        case (.pixels, let size?):
            widthField.stringValue = "\(Int(size.width))"
            heightField.stringValue = "\(Int(size.height))"
        case (.percent, let size?):
            widthField.stringValue = "\(Int((size.width / originalSize.width * 100).rounded()))"
            heightField.stringValue = "\(Int((size.height / originalSize.height * 100).rounded()))"
        default:
            break
        }
        syncing = false
        updateResultLabel()
    }

    @objc private func proportionalToggled(_ sender: NSButton) {
        if sender.state == .on { syncHeight(fromWidth: true) }
    }

    private func syncHeight(fromWidth: Bool) {
        syncing = true
        defer { syncing = false }
        let source = fromWidth ? widthField : heightField
        let target = fromWidth ? heightField : widthField
        guard let value = Double(source.stringValue.trimmingCharacters(in: .whitespaces)),
              value > 0 else { return }
        switch unit {
        case .percent:
            target.stringValue = source.stringValue
        case .pixels:
            let other = fromWidth ? value / aspect : value * aspect
            target.stringValue = "\(Int(other.rounded()))"
        }
    }
}

extension ResizeDialog: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard !syncing, let field = obj.object as? NSTextField else { return }
        if proportionalCheck.state == .on {
            syncHeight(fromWidth: field === widthField)
        }
        updateResultLabel()
    }
}
