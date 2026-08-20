import Cocoa
import Foundation

class StatusItem: NSObject {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard
    private let buttonImage = ButtonImage()
    private let spaceSwitcher = YabaiSpaceController()
    private var currentSpaceInfo = SpaceInfo(keyboardFocusSpace: nil, activeSpaces: [], allSpaces: [])
    private var currentButtonLayout = ButtonImageLayout(image: NSImage(size: .zero), segments: [])
    private var contextMenu = NSMenu()
    private var menuSignature = ""
    private var labelsPanelController: IndexLabelsPanelController?
    private var scrollEventMonitor: Any?
    private var globalScrollEventMonitor: Any?
    private var lastScrollSwitchTime: TimeInterval = 0
    private var pendingFocusedSpaceUUID: String?

    var delegate: ReloadDelegate? = nil

    override init() {
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemAction(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Left click a label to switch Space. Scroll through occupied Spaces. Right click for menu."
        }
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self = self, self.handleScrollEvent(event) else { return event }
            return nil
        }
        globalScrollEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            _ = self?.handleGlobalScrollEvent(event)
        }
    }

    deinit {
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalScrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func createMenu() {
        contextMenu = menuItems()
        menuSignature = currentMenuSignature()
    }

    func updateMenuImage(spaceInfo: SpaceInfo) {
        currentSpaceInfo = spaceInfo
        if pendingFocusedSpaceUUID == spaceInfo.keyboardFocusSpace?.uuid {
            pendingFocusedSpaceUUID = nil
        }
        updateButtonLayout()
        if currentMenuSignature() != menuSignature {
            createMenu()
        }
    }

    private func menuItems() -> NSMenu {
        let menu = NSMenu()
        let manageLabels = NSMenuItem(title: "Manage Index Icons…",
                                      action: #selector(openLabelsPanel(_:)),
                                      keyEquivalent: "")
        let pref = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        let opt = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "")
        manageLabels.target = self
        quit.target = self

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0"
        menu.addItem(NSMenuItem(title: "v\(version)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(manageLabels)
        menu.addItem(pref)
        menu.setSubmenu(preferenceMenu(), for: pref)
        menu.addItem(opt)
        menu.setSubmenu(optionMenu(), for: opt)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quit)
        return menu
    }

    private func preferenceMenu() -> NSMenu {
        let menu = NSMenu()
        let launchLogin = menuItem(title: "Launch on Login", action: #selector(launchOnLogin(_:)))
        launchLogin.state = defaults.bool(forKey: Preference.App.launchOnLogin.rawValue) ? .on : .off

        let oneIcon = menuItem(title: "One Icon", action: #selector(oneIcon(_:)))
        let perMonitor = menuItem(title: "Icon Per Monitor", action: #selector(iconPerMonitor(_:)))
        let perSpace = menuItem(title: "Icon Per Space", action: #selector(iconPerSpace(_:)))
        switch Preference.Icon(rawValue: defaults.integer(forKey: Preference.icon)) ?? .perSpace {
        case .one: oneIcon.state = .on
        case .perMonitor: perMonitor.state = .on
        case .perSpace: perSpace.state = .on
        }

        let whiteOnBlack = menuItem(title: "White on Black", action: #selector(whiteOnBlack(_:)))
        let blackOnWhite = menuItem(title: "Black on White", action: #selector(blackOnWhite(_:)))
        switch Preference.Color(rawValue: defaults.integer(forKey: Preference.color)) ?? .whiteOnBlack {
        case .whiteOnBlack: whiteOnBlack.state = .on
        case .blackOnWhite: blackOnWhite.state = .on
        }

        let font = NSMenuItem(title: "Label Font", action: nil, keyEquivalent: "")
        menu.setSubmenu(fontMenu(), for: font)

        menu.addItem(launchLogin)
        menu.addItem(.separator())
        menu.addItem(oneIcon)
        menu.addItem(perMonitor)
        menu.addItem(perSpace)
        menu.addItem(.separator())
        menu.addItem(whiteOnBlack)
        menu.addItem(blackOnWhite)
        menu.addItem(.separator())
        menu.addItem(font)
        return menu
    }

    private func fontMenu() -> NSMenu {
        let menu = NSMenu()
        let selectedFamily = defaults.string(forKey: Preference.fontFamily)
        let system = menuItem(title: "System", action: #selector(useSystemFont(_:)))
        system.state = selectedFamily == nil || selectedFamily?.isEmpty == true ? .on : .off
        menu.addItem(system)
        menu.addItem(.separator())

        let nerdFonts = NSFontManager.shared.availableFontFamilies
            .filter { family in
                family.range(of: "Nerd Font", options: .caseInsensitive) != nil
                    || family.range(of: "NerdFont", options: .caseInsensitive) != nil
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if nerdFonts.isEmpty {
            let unavailable = NSMenuItem(title: "No Nerd Fonts Installed",
                                         action: nil,
                                         keyEquivalent: "")
            unavailable.isEnabled = false
            menu.addItem(unavailable)
        } else {
            for family in nerdFonts {
                let font = menuItem(title: family, action: #selector(selectFont(_:)))
                font.representedObject = family
                font.state = family == selectedFamily ? .on : .off
                if let previewFont = fontForFamily(family, size: 13) {
                    font.attributedTitle = NSAttributedString(string: family,
                                                              attributes: [.font: previewFont])
                }
                menu.addItem(font)
            }
        }
        return menu
    }

    private func optionMenu() -> NSMenu {
        let menu = NSMenu()
        let leftClick = menuItem(title: "Update on Left Click",
                                 action: #selector(updateOnLeftClick(_:)))
        let appSwitch = menuItem(title: "Update on Application Switch",
                                 action: #selector(updateOnAppSwitch(_:)))
        let underline = menuItem(title: "Underline Active Monitor",
                                 action: #selector(underlineActiveMonitor(_:)))

        leftClick.state = defaults.bool(forKey: Preference.App.updateOnLeftClick.rawValue) ? .on : .off
        appSwitch.state = defaults.bool(forKey: Preference.App.updateOnAppSwitch.rawValue) ? .on : .off
        underline.state = defaults.bool(forKey: Preference.App.underlineActiveMonitor.rawValue) ? .on : .off

        menu.addItem(leftClick)
        menu.addItem(appSwitch)
        menu.addItem(.separator())
        menu.addItem(underline)
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func fontForFamily(_ family: String, size: CGFloat) -> NSFont? {
        let manager = NSFontManager.shared
        return manager.font(withFamily: family,
                            traits: .boldFontMask,
                            weight: 5,
                            size: size)
            ?? manager.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    @objc private func openLabelsPanel(_ sender: NSMenuItem) {
        labelsPanelController?.close()
        let labels = defaults.dictionary(forKey: Preference.indexLabels) as? [String: String] ?? [:]
        let maxIndexCount = max(1, defaults.integer(forKey: Preference.maxIndexCount))
        let controller = IndexLabelsPanelController(
            labels: labels,
            maxIndexCount: maxIndexCount,
            currentIndex: currentSpaceInfo.keyboardFocusSpace?.number
        ) { [weak self] updatedLabels, updatedMaxIndexCount in
            self?.saveIndexLabels(updatedLabels, maxIndexCount: updatedMaxIndexCount)
        }
        labelsPanelController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func saveIndexLabels(_ labels: [String: String], maxIndexCount: Int) {
        defaults.set(labels, forKey: Preference.indexLabels)
        defaults.set(maxIndexCount, forKey: Preference.maxIndexCount)
        updateMenuImage(spaceInfo: currentSpaceInfo)
    }

    private func currentMenuSignature() -> String {
        let labels = defaults.dictionary(forKey: Preference.indexLabels) as? [String: String] ?? [:]
        let spaces = currentSpaceInfo.allSpaces.map {
            let index = $0.number.map(String.init) ?? "F"
            return "\($0.uuid):\(index):\(labels[index] ?? "")"
        }.joined(separator: "|")
        return "\(currentSpaceInfo.keyboardFocusSpace?.uuid ?? "")|\(spaces)"
    }

    private func refreshAppearance() {
        updateButtonLayout()
        createMenu()
    }

    private func updateButtonLayout() {
        currentButtonLayout = buttonImage.createLayout(spaceInfo: currentSpaceInfo)
        item.button?.image = currentButtonLayout.image
    }

    @objc private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            createMenu()
            item.popUpMenu(contextMenu)
            return
        }

        guard event.type == .leftMouseUp,
              let space = clickedSpace(event: event, button: sender)
        else { return }
        switchToSpace(space)
    }

    private func clickedSpace(event: NSEvent, button: NSStatusBarButton) -> Space? {
        let point = button.convert(event.locationInWindow, from: nil)
        let imageOriginX = (button.bounds.width - currentButtonLayout.image.size.width) / 2
        let imageX = point.x - imageOriginX
        return currentButtonLayout.segments.first {
            imageX >= $0.frame.minX && imageX <= $0.frame.maxX
        }?.space
    }

    private func handleScrollEvent(_ event: NSEvent) -> Bool {
        guard let button = item.button,
              event.window === button.window,
              button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        else { return false }

        return handleScroll(delta: dominantScrollDelta(event),
                            timestamp: event.timestamp)
    }

    private func handleGlobalScrollEvent(_ event: NSEvent) -> Bool {
        guard let window = item.button?.window,
              window.frame.contains(NSEvent.mouseLocation)
        else { return false }

        return handleScroll(delta: dominantScrollDelta(event),
                            timestamp: event.timestamp)
    }

    private func dominantScrollDelta(_ event: NSEvent) -> CGFloat {
        return abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
    }

    private func handleScroll(delta: CGFloat,
                              timestamp: TimeInterval) -> Bool {
        guard abs(delta) > 0.01 else { return true }

        if timestamp - lastScrollSwitchTime < 0.22 {
            return true
        }
        lastScrollSwitchTime = timestamp

        let occupiedSpaces = currentSpaceInfo.allSpaces
            .filter { $0.hasApplicationWindows && $0.number != nil }
            .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
        guard !occupiedSpaces.isEmpty else { return true }

        let baseSpace = pendingFocusedSpaceUUID.flatMap { uuid in
            currentSpaceInfo.allSpaces.first { $0.uuid == uuid }
        } ?? currentSpaceInfo.keyboardFocusSpace
        let baseNumber = baseSpace?.number

        let target: Space?
        if delta > 0 {
            target = occupiedSpaces.last {
                guard let number = $0.number, let baseNumber = baseNumber else { return false }
                return number < baseNumber
            } ?? occupiedSpaces.last
        } else {
            target = occupiedSpaces.first {
                guard let number = $0.number, let baseNumber = baseNumber else { return false }
                return number > baseNumber
            } ?? occupiedSpaces.first
        }

        if let target = target {
            switchToSpace(target)
        }
        return true
    }

    private func switchToSpace(_ space: Space) {
        let currentUUID = pendingFocusedSpaceUUID ?? currentSpaceInfo.keyboardFocusSpace?.uuid
        guard space.uuid != currentUUID else { return }
        guard spaceSwitcher.switchTo(space: space) else {
            NSSound.beep()
            return
        }

        pendingFocusedSpaceUUID = space.uuid
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            self?.delegate?.refresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard self?.pendingFocusedSpaceUUID == space.uuid else { return }
            self?.pendingFocusedSpaceUUID = nil
        }
    }

    @objc private func oneIcon(_ sender: NSMenuItem) {
        defaults.set(Preference.Icon.one.rawValue, forKey: Preference.icon)
        refreshAppearance()
    }

    @objc private func iconPerMonitor(_ sender: NSMenuItem) {
        defaults.set(Preference.Icon.perMonitor.rawValue, forKey: Preference.icon)
        refreshAppearance()
    }

    @objc private func iconPerSpace(_ sender: NSMenuItem) {
        defaults.set(Preference.Icon.perSpace.rawValue, forKey: Preference.icon)
        refreshAppearance()
    }

    @objc private func whiteOnBlack(_ sender: NSMenuItem) {
        defaults.set(Preference.Color.whiteOnBlack.rawValue, forKey: Preference.color)
        refreshAppearance()
    }

    @objc private func blackOnWhite(_ sender: NSMenuItem) {
        defaults.set(Preference.Color.blackOnWhite.rawValue, forKey: Preference.color)
        refreshAppearance()
    }

    @objc private func useSystemFont(_ sender: NSMenuItem) {
        defaults.removeObject(forKey: Preference.fontFamily)
        refreshAppearance()
    }

    @objc private func selectFont(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? String else { return }
        defaults.set(family, forKey: Preference.fontFamily)
        refreshAppearance()
    }

    @objc private func updateOnLeftClick(_ sender: NSMenuItem) {
        let value = defaults.bool(forKey: Preference.App.updateOnLeftClick.rawValue)
        defaults.set(!value, forKey: Preference.App.updateOnLeftClick.rawValue)
        delegate?.reload()
    }

    @objc private func updateOnAppSwitch(_ sender: NSMenuItem) {
        let value = defaults.bool(forKey: Preference.App.updateOnAppSwitch.rawValue)
        defaults.set(!value, forKey: Preference.App.updateOnAppSwitch.rawValue)
        delegate?.reload()
    }

    @objc private func underlineActiveMonitor(_ sender: NSMenuItem) {
        let value = defaults.bool(forKey: Preference.App.underlineActiveMonitor.rawValue)
        defaults.set(!value, forKey: Preference.App.underlineActiveMonitor.rawValue)
        refreshAppearance()
    }

    @objc private func launchOnLogin(_ sender: NSMenuItem) {
        let value = !defaults.bool(forKey: Preference.App.launchOnLogin.rawValue)
        defaults.set(value, forKey: Preference.App.launchOnLogin.rawValue)
        delegate?.reload()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(self)
    }
}

private final class IndexLabelsPanelController: NSWindowController {

    private static let minimumIndexCount = 1
    private static let maximumIndexCount = 999

    private let currentIndex: Int?
    private let onSave: ([String: String], Int) -> Void
    private var draftLabels: [String: String]
    private var maxIndexCount: Int
    private var fields: [Int: NSTextField] = [:]
    private var scrollView: NSScrollView!
    private var countField: NSTextField!
    private var countStepper: NSStepper!

    init(labels: [String: String],
         maxIndexCount: Int,
         currentIndex: Int?,
         onSave: @escaping ([String: String], Int) -> Void) {
        self.draftLabels = labels
        self.maxIndexCount = min(max(maxIndexCount, Self.minimumIndexCount),
                                 Self.maximumIndexCount)
        self.currentIndex = currentIndex
        self.onSave = onSave

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 510),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Index Icons"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()

        super.init(window: panel)
        buildContent(width: 460, height: 510)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent(width: CGFloat, height: CGFloat) {
        guard let window = window else { return }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = content

        let help = NSTextField(labelWithString: "Icons and names follow the numeric index, not the macOS Space ID.")
        help.frame = NSRect(x: 20, y: height - 42, width: width - 40, height: 20)
        help.textColor = .secondaryLabelColor
        content.addSubview(help)

        let countLabel = NSTextField(labelWithString: "Max Index Count:")
        countLabel.frame = NSRect(x: 20, y: height - 76, width: 120, height: 22)
        content.addSubview(countLabel)

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: Self.minimumIndexCount)
        formatter.maximum = NSNumber(value: Self.maximumIndexCount)

        countField = NSTextField(frame: NSRect(x: 142, y: height - 79, width: 58, height: 24))
        countField.formatter = formatter
        countField.integerValue = maxIndexCount
        countField.target = self
        countField.action = #selector(changeIndexCountFromField(_:))
        content.addSubview(countField)

        countStepper = NSStepper(frame: NSRect(x: 204, y: height - 80, width: 19, height: 27))
        countStepper.minValue = Double(Self.minimumIndexCount)
        countStepper.maxValue = Double(Self.maximumIndexCount)
        countStepper.increment = 1
        countStepper.integerValue = maxIndexCount
        countStepper.valueWraps = false
        countStepper.autorepeat = true
        countStepper.target = self
        countStepper.action = #selector(changeIndexCountFromStepper(_:))
        content.addSubview(countStepper)

        scrollView = NSScrollView(frame: NSRect(x: 20, y: 62, width: width - 40, height: height - 154))
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)
        rebuildRows()

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.frame = NSRect(x: width - 190, y: 18, width: 80, height: 30)
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.frame = NSRect(x: width - 100, y: 18, width: 80, height: 30)
        save.keyEquivalent = "\r"
        content.addSubview(save)

        window.initialFirstResponder = currentIndex.flatMap { fields[$0] } ?? fields[1]
    }

    private func rebuildRows() {
        let rowHeight: CGFloat = 34
        let documentHeight = max(scrollView.contentSize.height,
                                 CGFloat(maxIndexCount) * rowHeight + 8)
        let document = FlippedView(frame: NSRect(x: 0,
                                                  y: 0,
                                                  width: scrollView.contentSize.width,
                                                  height: documentHeight))
        fields.removeAll()

        for index in 1...maxIndexCount {
            let y = CGFloat(index - 1) * rowHeight + 6
            var labelText = "Index \(index)"
            if index == currentIndex {
                labelText += "  • Current"
            }

            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 12, y: y + 3, width: 145, height: 22)
            label.lineBreakMode = .byTruncatingTail
            document.addSubview(label)

            let field = NSTextField(frame: NSRect(x: 164,
                                                   y: y,
                                                   width: document.frame.width - 178,
                                                   height: 24))
            field.stringValue = draftLabels[String(index)] ?? ""
            field.placeholderString = String(index)
            field.toolTip = "Paste a Nerd Font glyph, icon, or name. Empty values use the index number."
            field.font = labelFieldFont()
            document.addSubview(field)
            fields[index] = field
        }

        scrollView.hasVerticalScroller = maxIndexCount > 10
        scrollView.documentView = document
    }

    private func captureLabels() {
        for (index, field) in fields {
            let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty {
                draftLabels.removeValue(forKey: String(index))
            } else {
                draftLabels[String(index)] = label
            }
        }
    }

    private func updateMaxIndexCount(_ value: Int) {
        captureLabels()
        maxIndexCount = min(max(value, Self.minimumIndexCount), Self.maximumIndexCount)
        countField.integerValue = maxIndexCount
        countStepper.integerValue = maxIndexCount
        rebuildRows()
    }

    @objc private func changeIndexCountFromField(_ sender: NSTextField) {
        updateMaxIndexCount(sender.integerValue)
    }

    @objc private func changeIndexCountFromStepper(_ sender: NSStepper) {
        updateMaxIndexCount(sender.integerValue)
    }

    private func labelFieldFont() -> NSFont {
        guard let family = UserDefaults.standard.string(forKey: Preference.fontFamily),
              !family.isEmpty
        else { return NSFont.systemFont(ofSize: 13) }

        let manager = NSFontManager.shared
        return manager.font(withFamily: family, traits: [], weight: 5, size: 13)
            ?? NSFont.systemFont(ofSize: 13)
    }

    @objc private func save(_ sender: NSButton) {
        updateMaxIndexCount(countField.integerValue)
        captureLabels()
        var labels: [String: String] = [:]
        for index in 1...maxIndexCount {
            if let label = draftLabels[String(index)], !label.isEmpty {
                labels[String(index)] = label
            }
        }
        onSave(labels, maxIndexCount)
        close()
    }

    @objc private func cancel(_ sender: NSButton) {
        close()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}
