import AppKit

@MainActor
enum Clipboard {
    // Reads an image and its true pixel size (not point size, which differs
    // on Retina screenshots) from the general pasteboard.
    static func readImage() -> (NSImage, CGSize)? {
        guard let image = NSImage(pasteboard: .general) else { return nil }
        var pixelsWide = 0, pixelsHigh = 0
        for rep in image.representations {
            pixelsWide = max(pixelsWide, rep.pixelsWide)
            pixelsHigh = max(pixelsHigh, rep.pixelsHigh)
        }
        let size = (pixelsWide > 0 && pixelsHigh > 0)
            ? CGSize(width: pixelsWide, height: pixelsHigh)
            : image.size
        guard size.width >= 1, size.height >= 1 else { return nil }
        return (image, size)
    }

    // Writes the flattened canvas — or just `region` of it — as both PNG and
    // TIFF so every paste target (browsers, Mail, Office) finds a format it
    // accepts.
    static func copyFlattened(_ document: Document, region: CGRect? = nil) -> Bool {
        guard var rep = document.render() else { return false }
        if let region {
            let rect = region.integral
                .intersection(CGRect(origin: .zero, size: document.canvasSize))
            guard rect.width >= 1, rect.height >= 1,
                  let cgImage = rep.cgImage?.cropping(to: rect) else { return false }
            let cropped = NSBitmapImageRep(cgImage: cgImage)
            cropped.size = rect.size
            rep = cropped
        }
        guard let png = rep.representation(using: .png, properties: [:]),
              let tiff = rep.tiffRepresentation
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(tiff, forType: .tiff)
        return true
    }
}
