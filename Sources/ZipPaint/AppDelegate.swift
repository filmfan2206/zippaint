import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CanvasWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        controller = CanvasWindowController()
        controller.window?.center()
        controller.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.doc.hasMarkup else { return .terminateNow }
        return CanvasWindowController.confirmDiscard("Quit and discard your markup?")
            ? .terminateNow : .terminateCancel
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ZipPaint",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ZipPaint",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("Open…", #selector(CanvasWindowController.openImage(_:)), "o"))
        fileMenu.addItem(menuItem("Save As PNG…", #selector(CanvasWindowController.saveImage(_:)), "s"))
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem("Undo", #selector(CanvasWindowController.undo(_:)), "z"))
        editMenu.addItem(menuItem("Redo", #selector(CanvasWindowController.redo(_:)), "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("Copy Canvas", #selector(CanvasWindowController.copyCanvas(_:)), "c"))
        editMenu.addItem(menuItem("Paste Image", #selector(CanvasWindowController.pasteImage(_:)), "v"))
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem("Zoom In", #selector(CanvasWindowController.zoomInAction(_:)), "="))
        viewMenu.addItem(menuItem("Zoom Out", #selector(CanvasWindowController.zoomOutAction(_:)), "-"))
        viewMenu.addItem(menuItem("Actual Size", #selector(CanvasWindowController.zoomActualAction(_:)), "0"))
        viewItem.submenu = viewMenu

        let toolsItem = NSMenuItem()
        mainMenu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "Tools")
        let resizeItem = menuItem("Resize Image…", #selector(CanvasWindowController.resizeImage(_:)), "r")
        resizeItem.keyEquivalentModifierMask = [.command, .option]
        toolsMenu.addItem(resizeItem)
        toolsMenu.addItem(menuItem("Crop Image", #selector(CanvasWindowController.cropAction(_:)), "k"))
        let removeBackgroundItem = menuItem("Remove Background", #selector(CanvasWindowController.removeBackground(_:)), "k")
        removeBackgroundItem.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.addItem(removeBackgroundItem)
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(menuItem("Rotate Left", #selector(CanvasWindowController.rotateLeft(_:)), "l"))
        toolsMenu.addItem(menuItem("Rotate Right", #selector(CanvasWindowController.rotateRight(_:)), "r"))
        toolsMenu.addItem(menuItem("Flip Horizontal", #selector(CanvasWindowController.flipHorizontal(_:)), ""))
        toolsMenu.addItem(menuItem("Flip Vertical", #selector(CanvasWindowController.flipVertical(_:)), ""))
        toolsItem.submenu = toolsMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.miniaturize(_:)),
                           keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // No explicit target: the action resolves through the responder chain to
    // the key window's CanvasWindowController, and the item disables itself
    // when nothing in the chain handles it.
    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
