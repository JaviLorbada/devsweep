import AppKit
import SwiftUI

/// A view's accessibility tree as VoiceOver reads it: each element's role,
/// label, value and actions, in order. The view is hosted in a window of
/// its own, kept while the tree is, so its elements can be pressed. SwiftUI
/// builds the tree only for an assistive app (`AssistiveClient`).
@MainActor
struct AccessibilityTree {
    struct Element {
        let role: String
        let label: String
        let value: String
        let isSelected: Bool
        /// The names of its custom actions, such as "Select".
        let actions: [String]
        let children: [Element]
        fileprivate let object: NSObject

        /// A heading, which VoiceOver can jump between.
        var isHeading: Bool {
            self.role == "AXHeading"
        }

        /// Itself and everything inside it, depth first: the order VoiceOver reads them.
        var all: [Element] {
            [self] + self.children.flatMap(\.all)
        }

        /// VoiceOver's default action, VO-Space.
        func press() {
            _ = (self.object as AnyObject).accessibilityPerformPress?()
        }

        /// A custom action by its name, from VoiceOver's actions menu.
        func perform(_ name: String) {
            let action = (self.object as AnyObject).accessibilityCustomActions?()?.first { $0.name == name }
            _ = action?.handler?()
        }
    }

    let root: Element
    private let window: NSWindow

    init(_ view: some View, width: CGFloat, height: CGFloat) {
        precondition(AssistiveClient.isListening, "the application can't be told an assistive app is listening")
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        self.window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        self.window.contentView = host
        host.layoutSubtreeIfNeeded()
        self.root = Self.element(host)
    }

    /// Every element, depth first.
    var all: [Element] {
        self.root.all
    }

    /// The first element with this label.
    func first(_ label: String) -> Element? {
        self.all.first { $0.label == label }
    }

    private static func element(_ object: NSObject) -> Element {
        func text(_ key: String) -> String {
            guard object.responds(to: NSSelectorFromString(key)) else {
                return ""
            }
            return object.value(forKey: key).map { "\($0)" } ?? ""
        }
        let any = object as AnyObject
        let children = (any.accessibilityChildren?() ?? []).compactMap { $0 as? NSObject }
        return Element(
            role: text("accessibilityRole"),
            label: text("accessibilityLabel"),
            value: text("accessibilityValue"),
            isSelected: any.isAccessibilitySelected?() ?? false,
            actions: any.accessibilityCustomActions?()?.map(\.name) ?? [],
            children: children.map(self.element),
            object: object)
    }
}
