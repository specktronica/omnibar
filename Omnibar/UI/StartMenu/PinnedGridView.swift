import AppKit
import Foundation

final class PinnedGridView: NSView {
    var onLaunch: ((String) -> Void)?
    private let header = NSTextField(labelWithString: "Pinned Apps")
    private var buttons: [NSButton] = []
    private var renderedIDs: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        header.font = .boldSystemFont(ofSize: 13)
        addSubview(header)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ bundleIDs: [String]) {
        if bundleIDs == renderedIDs, buttons.count == bundleIDs.count { return }
        renderedIDs = bundleIDs

        var next: [NSButton] = []
        for (index, id) in bundleIDs.enumerated() {
            let button: NSButton
            if index < buttons.count {
                button = buttons[index]
            } else {
                button = NSButton(title: "", target: self, action: #selector(tap(_:)))
                button.bezelStyle = .shadowlessSquare
                button.isBordered = false
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyUpOrDown
                addSubview(button)
            }
            if button.identifier?.rawValue != id {
                button.identifier = NSUserInterfaceItemIdentifier(id)
                button.image = IconCache.icon(forBundleID: id)
                button.toolTip = IconCache.appName(for: id)
            }
            next.append(button)
        }
        if next.count < buttons.count {
            for extra in buttons[next.count...] {
                extra.removeFromSuperview()
            }
        }
        buttons = next
        needsLayout = true
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 20)
        let cols = 4
        let pad: CGFloat = 8
        let size: CGFloat = 44
        for (index, button) in buttons.enumerated() {
            let col = index % cols
            let row = index / cols
            button.frame = NSRect(
                x: CGFloat(col) * (size + pad),
                y: bounds.height - 28 - CGFloat(row + 1) * (size + pad),
                width: size,
                height: size
            )
        }
    }

    @objc private func tap(_ sender: NSButton) {
        onLaunch?(sender.identifier?.rawValue ?? "")
    }
}
