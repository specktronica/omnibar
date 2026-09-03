import AppKit
import Foundation

final class RecentAppsView: NSView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private let header = NSTextField(labelWithString: "Recent Apps")
    private var rows: [NSButton] = []
    private var apps: [AppCatalog.CatalogApp] = []
    private var renderedIDs: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        header.font = .boldSystemFont(ofSize: 13)
        addSubview(header)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ apps: [AppCatalog.CatalogApp]) {
        let ids = apps.map(\.id)
        if ids == renderedIDs, rows.count == apps.count {
            self.apps = apps
            return
        }
        renderedIDs = ids
        self.apps = apps

        var next: [NSButton] = []
        for (index, app) in apps.enumerated() {
            let button: NSButton
            if index < rows.count {
                button = rows[index]
            } else {
                button = NSButton(title: "", target: self, action: #selector(tap(_:)))
                button.bezelStyle = .shadowlessSquare
                button.isBordered = false
                button.imagePosition = .imageLeft
                button.alignment = .left
                addSubview(button)
            }
            button.title = " \(app.name)"
            button.image = IconCache.icon(for: app.url)
            button.tag = index
            next.append(button)
        }
        if next.count < rows.count {
            for extra in rows[next.count...] {
                extra.removeFromSuperview()
            }
        }
        rows = next
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
