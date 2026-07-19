import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [CanvasWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        newDocument(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controllers.contains(where: { $0.doc.hasMarkup }) else { return .terminateNow }
        return CanvasWindowController.confirmDiscard("Quit and discard your markup?")
            ? .terminateNow : .terminateCancel
    }

    // Each window is an independent document with its own tools and zoom.
    @objc func newDocument(_ sender: Any?) {
        let controller = CanvasWindowController()
        controller.onWindowClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        if let previous = controllers.last?.window, let window = controller.window {
            _ = window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX,
                                                    y: previous.frame.maxY))
        } else {
            controller.window?.center()
        }
        controllers.append(controller)
        controller.showWindow(nil)
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
        fileMenu.addItem(menuItem("New", #selector(AppDelegate.newDocument(_:)), "n"))
        fileMenu.addItem(menuItem("Open…", #selector(CanvasWindowController.openImage(_:)), "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Close Window", #selector(NSWindow.performClose(_:)), "w"))
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
