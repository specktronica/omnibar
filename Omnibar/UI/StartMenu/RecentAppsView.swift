import AppKit
import Foundation

final class RecentAppsView: NSView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private let header = NSTextField(labelWithString: "Recent Apps")
    private var rows: [NSButton] = []
    private var apps: [AppCatalog.CatalogApp] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        header.font = .boldSystemFont(ofSize: 13)
        addSubview(header)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ apps: [AppCatalog.CatalogApp]) {
        self.apps = apps
        rows.forEach { $0.removeFromSuperview() }
        rows = apps.enumerated().map { index, app in
            let button = NSButton(title: " \(app.name)", target: self, action: #selector(tap(_:)))
            button.bezelStyle = .shadowlessSquare
            button.isBordered = false
            button.image = IconCache.icon(for: app.url)
            button.imagePosition = .imageLeft
            button.alignment = .left
            button.tag = index
            addSubview(button)
            return button
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 20)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y: bounds.height - 50 - CGFloat(index) * 28,
                width: bounds.width,
                height: 26
            )
        }
    }

    @objc private func tap(_ sender: NSButton) {
        guard apps.indices.contains(sender.tag) else { return }
        onLaunch?(apps[sender.tag])
    }
}
