import AppKit
import Foundation

final class AppListView: NSScrollView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private let stack = NSStackView()
    private var rows: [AppRow] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.addSubview(stack)
        documentView = document
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(_ groups: [(letter: String, apps: [AppCatalog.CatalogApp])]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()
        for group in groups {
            let header = NSTextField(labelWithString: group.letter)
            header.font = .boldSystemFont(ofSize: 13)
            header.textColor = .secondaryLabelColor
            stack.addArrangedSubview(header)
            for app in group.apps {
                let row = AppRow(app: app)
                row.onLaunch = { [weak self] in self?.onLaunch?(app) }
                stack.addArrangedSubview(row)
                rows.append(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
    }
}

private final class AppRow: NSView {
    var onLaunch: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hovered = false

    init(app: AppCatalog.CatalogApp) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.image = IconCache.icon(for: app.url)
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.stringValue = app.name
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 6, y: 4, width: 20, height: 20)
        label.frame = NSRect(x: 32, y: 4, width: bounds.width - 40, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        layer?.backgroundColor = nil
    }

    override func mouseUp(with event: NSEvent) {
        onLaunch?()
    }
}
