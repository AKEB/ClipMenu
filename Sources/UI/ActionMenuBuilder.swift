import AppKit

/// Builds a native NSMenu from an ActionNode tree for modifier-click popups.
enum ActionMenuBuilder {

    static func makeMenu(from roots: [ActionNode], target: ClipEntry, service: ActionService) -> NSMenu {
        let menu = NSMenu()
        let sortedRoots = roots
            .filter(\.isEnabled)
            .sorted { $0.sortIndex < $1.sortIndex }

        for node in sortedRoots {
            menu.addItem(makeItem(for: node, target: target, service: service))
        }

        return menu
    }

    private static func makeItem(for node: ActionNode, target: ClipEntry, service: ActionService) -> NSMenuItem {
        if node.isLeaf {
            let item = NSMenuItem(title: node.title, action: #selector(ActionMenuTarget.perform(_:)), keyEquivalent: "")
            item.target = ActionMenuTarget.shared
            item.representedObject = ActionMenuInvocation {
                Task { await service.perform(action: node, on: target) }
            }
            return item
        }

        let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: node.title)
        let sortedChildren = node.children
            .filter(\.isEnabled)
            .sorted { $0.sortIndex < $1.sortIndex }

        for child in sortedChildren {
            submenu.addItem(makeItem(for: child, target: target, service: service))
        }

        item.submenu = submenu
        return item
    }
}

/// Bridges NSMenuItem callbacks to async ActionService calls.
final class ActionMenuTarget: NSObject {
    static let shared = ActionMenuTarget()

    @objc func perform(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? ActionMenuInvocation else { return }
        invocation.invoke()
    }
}

private final class ActionMenuInvocation: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func invoke() {
        handler()
    }
}
