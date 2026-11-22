import AppKit

// Above Finder's desktop surface so the banner remains editable, below every normal app window.
let desktopBannerLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
let preferences = isSmokeTest ? UserDefaults(suiteName: "local.melissa.daily-banner.smoke")! : UserDefaults.standard

struct BannerState: Codable {
    var text = "慢慢来，也是在向前。"
    var family = "PingFang SC"
    var size: Double = 32
    var bold = false
    var rgba: [Double] = [0.14, 0.16, 0.18, 1]
    var frame: String?
    var centered = true
    var lineSpacing: Double = 5

    enum CodingKeys: String, CodingKey { case text, family, size, bold, rgba, frame, centered, lineSpacing }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? text
        family = try values.decodeIfPresent(String.self, forKey: .family) ?? family
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? size
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? bold
        rgba = try values.decodeIfPresent([Double].self, forKey: .rgba) ?? rgba
        frame = try values.decodeIfPresent(String.self, forKey: .frame)
        centered = try values.decodeIfPresent(Bool.self, forKey: .centered) ?? true
        lineSpacing = min(48, max(0, try values.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 5))
    }

    static func load() -> BannerState {
        guard let data = preferences.data(forKey: "banner"),
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return state
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { preferences.set(data, forKey: "banner") }
    }
    var color: NSColor {
        guard rgba.count == 4 else { return .labelColor }
        return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }
    var font: NSFont {
        let pointSize = min(160, max(10, size))
        return NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: bold ? .bold : .regular)
    }
}

final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class BannerTextView: NSTextView {
    var toggleBold: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": toggleBold?(); return true
            case "a": selectAll(nil); return true
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "x": cut(nil); return true
            case "z": undoManager?.undo(); return true
            default: break
            }
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            undoManager?.redo(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class DragHandle: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.65).setFill()
        for x in [15.0, 20.0, 25.0] {
            for y in [13.0, 18.0] { NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill() }
        }
    }
}

final class ResizeHandle: NSView {
    private var startPoint = NSPoint.zero
    private var startFrame = NSRect.zero
    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let width = min(window.maxSize.width, max(window.minSize.width, startFrame.width + point.x - startPoint.x))
        let height = min(window.maxSize.height, max(window.minSize.height, startFrame.height - point.y + startPoint.y))
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.65).setStroke()
        for offset in [0.0, 5.0] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.width - 7 - offset, y: 6))
            path.line(to: NSPoint(x: bounds.width - 6, y: 7 + offset))
            path.lineWidth = 1.2
            path.stroke()
        }
    }
}

final class BannerView: NSView {
    let toolbar = NSView()
    let grip = DragHandle()
    let resizeGrip = ResizeHandle()
    let scroll = NSScrollView()
    let editor = BannerTextView(frame: .zero)
    var tracking: NSTrackingArea?
    private var hoverTimer: Timer?
    var layoutToolbar: ((CGFloat) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.62).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        appearance = NSAppearance(named: .aqua)
        addSubview(scroll)
        addSubview(toolbar)
        toolbar.addSubview(grip)
        addSubview(resizeGrip)
        toolbar.isHidden = true
        resizeGrip.isHidden = true

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = editor
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(width: 4, height: 8)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("每日一句文字")
        grip.toolTip = "拖动以移动横幅"
        resizeGrip.toolTip = "拖动以调整大小"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        updateControlsForPointer()
        window?.performDrag(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard window != nil else { setControlsVisible(false); return }
        // Native menus and desktop activation can swallow mouseExited. Reconcile
        // against the real pointer position, including while a menu tracks input.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateControlsForPointer()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        updateControlsForPointer()
    }
    deinit { hoverTimer?.invalidate() }
    func updateControlsForPointer(at screenPoint: NSPoint = NSEvent.mouseLocation) {
        guard let window, window.isVisible, !window.isMiniaturized else {
            setControlsVisible(false)
            return
        }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        setControlsVisible(bounds.contains(point))
    }
    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: 0, y: bounds.height - 34, width: bounds.width, height: 32)
        grip.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        layoutToolbar?(bounds.width)
        resizeGrip.frame = NSRect(x: bounds.width - 24, y: 0, width: 24, height: 24)
        scroll.frame = NSRect(x: 20, y: 24, width: max(1, bounds.width - 40), height: max(1, bounds.height - 58))
        centerText()
    }
    func centerText() {
        guard let container = editor.textContainer, let manager = editor.layoutManager else { return }
        let viewport = scroll.contentSize
        container.containerSize = NSSize(width: max(1, viewport.width - 8), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let textHeight = max(editor.font?.pointSize ?? 32, manager.usedRect(for: container).height)
        let inset = max(8, (viewport.height - textHeight) / 2)
        editor.textContainerInset = NSSize(width: 4, height: inset)
        editor.minSize = NSSize(width: 0, height: viewport.height)
        editor.setFrameSize(NSSize(width: viewport.width, height: max(viewport.height, textHeight + inset * 2)))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        tracking = next
    }
    override func mouseEntered(with event: NSEvent) { updateControlsForPointer() }
    override func mouseMoved(with event: NSEvent) { updateControlsForPointer() }
    override func mouseExited(with event: NSEvent) { setControlsVisible(false) }
    func setControlsVisible(_ visible: Bool) {
        guard toolbar.isHidden != !visible else { return }
        toolbar.isHidden = !visible
        resizeGrip.isHidden = !visible
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, NSComboBoxDelegate {
    var state = BannerState.load()
    var panel: BannerPanel!
    var content: BannerView!
    var statusItem: NSStatusItem!
    let familyPicker = NSPopUpButton()
    let sizePicker = NSComboBox()
    let colorPicker = NSButton()
    let colorChoices: [(String, NSColor)] = [
        ("黑色", NSColor(srgbRed: 0.14, green: 0.16, blue: 0.18, alpha: 1)),
        ("白色", .white), ("灰色", .gray), ("红色", .systemRed),
        ("橙色", .systemOrange), ("绿色", .systemGreen),
        ("蓝色", .systemBlue), ("紫色", .systemPurple)
    ]
    let boldButton = NSButton(title: "B", target: nil, action: nil)
    let centerButton = NSButton()
    let spacingPicker = NSPopUpButton()

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenus()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initial = NSRect(x: screen.midX - 340, y: screen.maxY - 220, width: 680, height: 150)
        panel = BannerPanel(contentRect: initial, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "每日一句"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = false
        panel.level = desktopBannerLevel
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 380, height: 110)
        panel.maxSize = NSSize(width: 3000, height: 1600)
        panel.delegate = self
        content = BannerView(frame: NSRect(origin: .zero, size: initial.size))
        panel.contentView = content
        content.editor.delegate = self
        content.editor.toggleBold = { [weak self] in self?.toggleBold(nil) }
        content.editor.string = state.text
        makeToolbar()
        applyStyle()
        if let saved = state.frame {
            let frame = NSRectFromString(saved)
            if frame.width.isFinite && frame.height.isFinite && frame.width >= 380 && frame.height >= 110 {
                let screenFrame = NSScreen.screens.map(\.visibleFrame).first { $0.intersects(frame) } ?? screen
                let width = min(frame.width, screenFrame.width)
                let height = min(frame.height, screenFrame.height)
                panel.setFrame(NSRect(x: min(max(frame.minX, screenFrame.minX), screenFrame.maxX - width),
                                      y: min(max(frame.minY, screenFrame.minY), screenFrame.maxY - height),
                                      width: width, height: height), display: false)
            }
        }
        panel.orderFrontRegardless()
        content.needsLayout = true
        if isSmokeTest { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.smokeTest() } }
    }

    func makeMenus() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出每日一句", action: #selector(quit), keyEquivalent: "q").target = self
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.and.pencil.and.ellipsis", accessibilityDescription: "每日一句")
        statusItem.button?.toolTip = "每日一句"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示／隐藏横幅", action: #selector(toggleVisibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出每日一句", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }
    func makeToolbar() {
        familyPicker.frame = NSRect(x: 43, y: 4, width: 161, height: 25)
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        familyPicker.addItems(withTitles: families)
        familyPicker.selectItem(withTitle: state.family)
        familyPicker.font = .systemFont(ofSize: 11)
        familyPicker.target = self; familyPicker.action = #selector(changeFamily)
        familyPicker.toolTip = "字体"; familyPicker.setAccessibilityLabel("字体")
        sizePicker.frame = NSRect(x: 210, y: 5, width: 62, height: 23)
        sizePicker.addItems(withObjectValues: [14, 18, 24, 28, 32, 36, 48, 64, 72, 96])
        sizePicker.stringValue = String(Int(state.size))
        sizePicker.font = .systemFont(ofSize: 11)
        sizePicker.target = self; sizePicker.action = #selector(changeSize)
        sizePicker.delegate = self
        sizePicker.toolTip = "字号（10–160）"; sizePicker.setAccessibilityLabel("字号")
        colorPicker.frame = NSRect(x: 280, y: 5, width: 30, height: 23)
        colorPicker.title = ""
        colorPicker.bezelStyle = .texturedRounded
        colorPicker.imagePosition = .imageOnly
        updateColorSwatch()
        colorPicker.target = self; colorPicker.action = #selector(showColorMenu)
        colorPicker.toolTip = "文字颜色"; colorPicker.setAccessibilityLabel("文字颜色")
        boldButton.frame = NSRect(x: 318, y: 4, width: 32, height: 25)
        boldButton.bezelStyle = .texturedRounded
        boldButton.setButtonType(.toggle)
        boldButton.font = .boldSystemFont(ofSize: 13)
        boldButton.state = state.bold ? .on : .off
        boldButton.target = self; boldButton.action = #selector(toggleBold)
        boldButton.toolTip = "加粗（⌘B）"; boldButton.setAccessibilityLabel("加粗")
        centerButton.title = ""
        centerButton.image = NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "居中对齐")
        centerButton.bezelStyle = .texturedRounded
        centerButton.setButtonType(.toggle)
        centerButton.state = state.centered ? .on : .off
        centerButton.target = self; centerButton.action = #selector(toggleCenter)
        centerButton.toolTip = "居中对齐（关闭后左对齐）"; centerButton.setAccessibilityLabel("居中对齐")
        for value in [0, 3, 5, 8, 12, 18, 24, 32, 48] {
            spacingPicker.addItem(withTitle: "行距 \(value)")
            spacingPicker.lastItem?.tag = value
        }
        spacingPicker.selectItem(withTag: Int(state.lineSpacing))
        spacingPicker.font = .systemFont(ofSize: 11)
        spacingPicker.target = self; spacingPicker.action = #selector(changeSpacing)
        spacingPicker.toolTip = "额外行间距（点），多行文字时生效"; spacingPicker.setAccessibilityLabel("行间距")
        for control in [familyPicker, sizePicker, colorPicker, boldButton, centerButton, spacingPicker] as [NSView] { content.toolbar.addSubview(control) }
        content.layoutToolbar = { [weak self] width in self?.layoutToolbar(width: width) }
        layoutToolbar(width: content.bounds.width)
    }
    func layoutToolbar(width: CGFloat) {
        // Fit every control even at the smallest supported banner width.
        let fontWidth = min(161, max(100, width - 280))
        var x: CGFloat = 34
        for (control, controlWidth) in [(familyPicker as NSView, fontWidth), (sizePicker, 54), (colorPicker, 28), (boldButton, 28), (centerButton, 28), (spacingPicker, 70)] {
            control.frame = NSRect(x: x, y: 4, width: controlWidth, height: 25)
            x += controlWidth + 6
        }
    }
    func applyStyle() {
        let range = content.editor.selectedRange()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = state.centered ? .center : .left
        paragraph.lineSpacing = state.lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [.font: state.font, .foregroundColor: state.color, .paragraphStyle: paragraph]
        content.editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (content.editor.string as NSString).length))
        content.editor.typingAttributes = attributes
        content.editor.font = state.font
        content.editor.textColor = state.color
        content.editor.insertionPointColor = state.color
        content.editor.defaultParagraphStyle = paragraph
        content.editor.setSelectedRange(range)
        content.centerText()
    }
    @objc func changeFamily() { state.family = familyPicker.titleOfSelectedItem ?? "PingFang SC"; applyStyle(); save() }
    @objc func toggleCenter() {
        state.centered.toggle()
        centerButton.state = state.centered ? .on : .off
        applyStyle(); save()
    }
    @objc func changeSpacing() {
        guard let item = spacingPicker.selectedItem else { return }
        state.lineSpacing = Double(item.tag)
        applyStyle(); save()
    }
    @objc func changeSize() {
        guard let number = Double(sizePicker.stringValue), number.isFinite else { sizePicker.stringValue = String(Int(state.size)); return }
        state.size = min(160, max(10, number))
        sizePicker.stringValue = String(Int(state.size))
        applyStyle(); save()
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        let index = sizePicker.indexOfSelectedItem
        if index >= 0 { sizePicker.stringValue = "\(sizePicker.itemObjectValue(at: index))"; changeSize() }
    }
    func controlTextDidEndEditing(_ notification: Notification) { changeSize() }
    func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill(); circle.fill()
            NSColor.gray.withAlphaComponent(0.5).setStroke(); circle.lineWidth = 0.5; circle.stroke()
            return true
        }
    }
    func updateColorSwatch() { colorPicker.image = swatch(state.color) }
    @objc func showColorMenu() {
        let menu = NSMenu()
        for (index, choice) in colorChoices.enumerated() {
            let item = NSMenuItem(title: choice.0, action: #selector(choosePresetColor(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.image = swatch(choice.1)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "自定义颜色…", action: #selector(showCustomColor), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: colorPicker.bounds.minY), in: colorPicker)
    }
    @objc func choosePresetColor(_ sender: NSMenuItem) {
        guard colorChoices.indices.contains(sender.tag) else { return }
        setTextColor(colorChoices[sender.tag].1)
    }
    @objc func showCustomColor() {
        let chooser = NSColorPanel.shared
        chooser.setTarget(self)
        chooser.setAction(#selector(customColorChanged(_:)))
        chooser.isContinuous = true
        chooser.showsAlpha = false
        chooser.mode = .wheel
        chooser.color = state.color
        chooser.title = "文字颜色"
        chooser.hidesOnDeactivate = true
        NSApp.activate(ignoringOtherApps: true)
        chooser.makeKeyAndOrderFront(nil)
    }
    @objc func customColorChanged(_ sender: NSColorPanel) { setTextColor(sender.color) }
    func setTextColor(_ selected: NSColor) {
        guard let color = selected.usingColorSpace(.sRGB) else { return }
        state.rgba = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        updateColorSwatch(); applyStyle(); save()
    }
    @objc func toggleBold(_ sender: Any?) {
        state.bold.toggle(); boldButton.state = state.bold ? .on : .off; applyStyle(); save()
    }
    func textDidChange(_ notification: Notification) { content.centerText(); save() }
    func windowDidMove(_ notification: Notification) { save() }
    func windowDidResize(_ notification: Notification) { content?.needsLayout = true; save() }
    func windowDidResignKey(_ notification: Notification) { save() }
    func save() {
        guard content != nil, panel != nil else { return }
        state.text = content.editor.string
        state.frame = NSStringFromRect(panel.frame)
        state.save()
    }
    @objc func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    @objc func quit() { save(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { save() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panel.orderFrontRegardless(); return true }

    func smokeTest() {
        let original = state
        let legacy = Data(#"{"text":"保留原来的话","family":"Times New Roman","size":32,"bold":true,"rgba":[0.2,0.3,0.4,1],"frame":"{{100, 100}, {565, 133}}"}"#.utf8)
        let migrated = try! JSONDecoder().decode(BannerState.self, from: legacy)
        precondition(migrated.text == "保留原来的话" && migrated.centered && migrated.lineSpacing == 5)
        content.editor.string = "今天，也给自己一点耐心。\nA small step is still a step."
        sizePicker.stringValue = "48"; changeSize()
        toggleBold(nil)
        familyPicker.selectItem(withTitle: "Helvetica Neue"); changeFamily()
        // Exercise the same target/action path as the color menu with the toolbar hidden.
        content.setControlsVisible(false)
        for index in [3, 6, 7] {
            let item = NSMenuItem(); item.tag = index
            choosePresetColor(item)
            let expected = colorChoices[index].1.usingColorSpace(.sRGB)!
            let actual = content.editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            precondition(actual == expected)
            precondition((content.editor.typingAttributes[.foregroundColor] as? NSColor) == expected)
            precondition(BannerState.load().rgba == state.rgba)
        }
        let chooser = NSColorPanel.shared
        chooser.color = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        customColorChanged(chooser)
        precondition(abs(state.rgba[1] - 0.6) < 0.001)
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.minY, width: 480, height: 220), display: true)
        content.layoutSubtreeIfNeeded()
        toggleCenter()
        precondition(!state.centered && content.editor.defaultParagraphStyle?.alignment == .left)
        toggleCenter()
        spacingPicker.selectItem(withTag: 0); changeSpacing()
        content.centerText()
        let compactHeight = content.editor.layoutManager!.usedRect(for: content.editor.textContainer!).height
        spacingPicker.selectItem(withTag: 24); changeSpacing()
        content.centerText()
        let spacedHeight = content.editor.layoutManager!.usedRect(for: content.editor.textContainer!).height
        precondition(spacedHeight > compactHeight)
        let paragraph = content.editor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        precondition(paragraph.alignment == .center && paragraph.lineSpacing == 24)
        layoutToolbar(width: 380)
        precondition(spacingPicker.frame.maxX <= 380)
        layoutToolbar(width: content.bounds.width)
        save()
        let loaded = BannerState.load()
        precondition(loaded.text == content.editor.string && loaded.size == 48 && loaded.bold)
        precondition(loaded.family == "Helvetica Neue" && loaded.frame == NSStringFromRect(panel.frame))
        precondition(loaded.rgba == state.rgba)
        precondition(loaded.centered && loaded.lineSpacing == 24)
        precondition(content.editor.frame.height >= content.scroll.contentSize.height)
        precondition(panel.level == desktopBannerLevel && !panel.isFloatingPanel && !panel.hidesOnDeactivate && !panel.isOpaque)
        precondition(panel.level.rawValue < NSWindow.Level.normal.rawValue)
        precondition(panel.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)))
        precondition(!panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.makeKeyAndOrderFront(nil)
        precondition(panel.level == desktopBannerLevel)
        panel.makeFirstResponder(content.editor)
        let inside = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let outside = NSPoint(x: panel.frame.maxX + 20, y: panel.frame.midY)
        content.updateControlsForPointer(at: inside)
        precondition(!content.toolbar.isHidden && !content.resizeGrip.isHidden)
        content.updateControlsForPointer(at: outside)
        precondition(content.toolbar.isHidden && content.resizeGrip.isHidden)
        precondition(panel.firstResponder === content.editor)
        content.updateControlsForPointer(at: inside)
        precondition(!content.toolbar.isHidden)
        toggleVisibility(); toggleVisibility()
        precondition(panel.isVisible && panel.level == desktopBannerLevel)
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        precondition(panel.level == desktopBannerLevel)
        sizePicker.stringValue = "999"; changeSize(); precondition(state.size == 160)
        sizePicker.stringValue = "invalid"; changeSize(); precondition(state.size == 160)
        state = original; content.editor.string = original.text; applyStyle()
        print("PASS: legacy data migration; center alignment; multiline spacing changes layout and persists; toolbar fits minimum width; hover, colors, desktop layer")
        preferences.removePersistentDomain(forName: "local.melissa.daily-banner.smoke")
        exit(0)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
