import Cocoa
import Foundation

struct ButtonImageSegment {
    let space: Space
    let frame: NSRect
}

struct ButtonImageLayout {
    let image: NSImage
    let segments: [ButtonImageSegment]
}

class ButtonImage {
    
    private let height: CGFloat = 17
    private let minimumWidth: CGFloat = 16
    private let horizontalPadding: CGFloat = 4
    private let spacing: CGFloat = 5
    private let defaults = UserDefaults.standard
    
    func createLayout(spaceInfo: SpaceInfo) -> ButtonImageLayout {
        let labels = defaults.dictionary(forKey: Preference.indexLabels) as? [String: String] ?? [:]
        let icon = Preference.Icon(rawValue: defaults.integer(forKey: Preference.icon)) ?? .perSpace
        let color = Preference.Color(rawValue: defaults.integer(forKey: Preference.color)) ?? .whiteOnBlack
        let underline = defaults.bool(forKey: Preference.App.underlineActiveMonitor.rawValue)

        switch icon {
        case .one:
            guard let current = spaceInfo.keyboardFocusSpace else {
                return emptyLayout()
            }
            let image = labelImage(text: displayLabel(for: current, labels: labels),
                                   color: color,
                                   alpha: 1,
                                   underline: false)
            return ButtonImageLayout(
                image: image,
                segments: [ButtonImageSegment(space: current,
                                              frame: NSRect(origin: .zero, size: image.size))]
            )

        case .perMonitor:
            let spaces = spaceInfo.activeSpaces.sorted { $0.order < $1.order }
            let icons = spaces.map { space in
                (space: space,
                 image: labelImage(text: displayLabel(for: space, labels: labels),
                                   color: color,
                                   alpha: 1,
                                   underline: underline && space.uuid == spaceInfo.keyboardFocusSpace?.uuid))
            }
            return combine(icons: icons)

        case .perSpace:
            let currentUUID = spaceInfo.keyboardFocusSpace?.uuid
            let spaces = spaceInfo.allSpaces.filter {
                // Keep the visible Space from every display. Previously this only
                // kept the keyboard-focus Space, so an empty visible Space on a
                // secondary display disappeared from the item on the main display.
                $0.isActive || $0.uuid == currentUUID || $0.hasApplicationWindows
            }
            let icons = spaces.map { space in
                (space: space,
                 image: labelImage(text: displayLabel(for: space, labels: labels),
                                   color: color,
                                   alpha: space.isActive ? 1 : 0.3,
                                   underline: underline && space.uuid == currentUUID))
            }
            return combine(icons: icons)
        }
    }

    private func textAttributes(color: NSColor, underline: Bool) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.center
        
        return [ .font: labelFont(),
                 .foregroundColor: color,
                 .paragraphStyle: paragraphStyle,
                 .underlineStyle: underline ? NSUnderlineStyle.single.rawValue : 0
               ]
    }

    private func labelImage(text: String,
                            color: Preference.Color,
                            alpha: CGFloat,
                            underline: Bool) -> NSImage {
        let drawingColor = NSColor(white: 0, alpha: alpha)
        let attributes = textAttributes(color: drawingColor, underline: underline)
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let width = max(minimumWidth, textWidth + horizontalPadding * 2)
        let size = CGSize(width: width, height: height)
        let rect = NSRect(origin: .zero, size: size)
        let image = NSImage(size: size)

        image.lockFocus()
        switch color {
        case .whiteOnBlack:
            drawingColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            text.drawVerticallyCentered(
                in: rect,
                withAttributes: textAttributes(color: .black, underline: underline))

        case .blackOnWhite:
            drawingColor.setStroke()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1),
                                    xRadius: 2,
                                    yRadius: 2)
            path.lineWidth = 2
            path.stroke()
            text.drawVerticallyCentered(in: rect, withAttributes: attributes)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func combine(icons: [(space: Space, image: NSImage)]) -> ButtonImageLayout {
        guard !icons.isEmpty else { return emptyLayout() }
        let width = icons.reduce(0) { $0 + $1.image.size.width } + spacing * CGFloat(icons.count - 1)
        let image = NSImage(size: CGSize(width: width, height: height))
        var segments: [ButtonImageSegment] = []
        image.lockFocus()
        var x: CGFloat = 0
        for icon in icons {
            icon.image.draw(at: NSPoint(x: x, y: 0),
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1)
            segments.append(ButtonImageSegment(
                space: icon.space,
                frame: NSRect(x: x, y: 0, width: icon.image.size.width, height: height)
            ))
            x += icon.image.size.width + spacing
        }
        image.unlockFocus()
        image.isTemplate = true
        return ButtonImageLayout(image: image, segments: segments)
    }

    private func displayLabel(for space: Space, labels: [String: String]) -> String {
        guard let index = space.number else { return "F" }
        let key = String(index)
        // Labels belong to the numeric position. A Space UUID can move to a
        // different position when Spaces are reordered, so it must not be used
        // as the preference key.
        return labels[key].flatMap { $0.isEmpty ? nil : $0 } ?? key
    }

    private func labelFont() -> NSFont {
        guard let family = defaults.string(forKey: Preference.fontFamily), !family.isEmpty else {
            return NSFont.boldSystemFont(ofSize: 11)
        }
        let manager = NSFontManager.shared
        return manager.font(withFamily: family,
                            traits: .boldFontMask,
                            weight: 5,
                            size: 11)
            ?? manager.font(withFamily: family, traits: [], weight: 5, size: 11)
            ?? NSFont.boldSystemFont(ofSize: 11)
    }

    private func emptyLayout() -> ButtonImageLayout {
        return ButtonImageLayout(image: NSImage(size: CGSize(width: minimumWidth, height: height)),
                                 segments: [])
    }
}

extension NSString {
    func drawVerticallyCentered(
        in rect: CGRect,
        withAttributes attributes: [NSAttributedString.Key : Any]? = nil)
    {
        let size = self.size(withAttributes: attributes)
        let centeredRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y + (rect.size.height-size.height)/2.0,
            width: rect.size.width,
            height: size.height
        )
        self.draw(in: centeredRect, withAttributes: attributes)
    }
}
