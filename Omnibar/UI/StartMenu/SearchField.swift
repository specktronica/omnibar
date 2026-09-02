import AppKit

final class SearchField: NSSearchField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        placeholderString = "Search"
        sendsSearchStringImmediately = true
        sendsWholeSearchString = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
