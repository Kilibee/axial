import AppKit
import SwiftUI

enum AxialAppearance {
    // Existing window and right-pane tint; sidebar adds no tint or background.
    static let glassTint = NSColor(srgbRed: 0.12, green: 0.51, blue: 0.68, alpha: 0.28)
    static let glassColor = Color(nsColor: glassTint)
}

struct PopupChoice: Equatable {
    let id: String
    let title: String
    init(_ id: String, _ title: String) {self.id = id;self.title = title}
}

// NSPopUpButton respects the full proposed width, including its native bezel.
// SwiftUI's menu-style Picker keeps an intrinsic-width bezel inside a wider frame.
struct NativePopup: NSViewRepresentable {
    let label: String
    var selection: String = ""
    let choices: [PopupChoice]
    var actionMenu = false
    var height: CGFloat = 26
    let choose: (String) -> Void
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject {
        var choices: [PopupChoice] = []
        var label = ""
        var choose: (String) -> Void = {_ in}
        @objc func changed(_ sender: NSPopUpButton) {
            if let id = sender.selectedItem?.representedObject as? String {choose(id)}
        }
    }
    func makeCoordinator() -> Coordinator {Coordinator()}
    func makeNSView(context: Context) -> NSPopUpButton {
        let control = NSPopUpButton(frame: .zero, pullsDown: actionMenu)
        control.bezelStyle = .rounded;control.isBordered = false
        control.controlSize = height >= 30 ? .large : .regular
        control.font = .systemFont(ofSize: NSFont.systemFontSize)
        control.target = context.coordinator;control.action = #selector(Coordinator.changed(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }
    func updateNSView(_ control: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator;coordinator.choose = choose
        if coordinator.choices != choices || coordinator.label != label {
            control.removeAllItems()
            if actionMenu {control.addItem(withTitle: label)}
            for choice in choices {
                let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
                item.representedObject = choice.id;control.menu?.addItem(item)
            }
            coordinator.choices = choices;coordinator.label = label
        }
        if !actionMenu, let index = choices.firstIndex(where: {$0.id == selection}), control.indexOfSelectedItem != index {control.selectItem(at: index)}
        control.isEnabled = enabled;control.setAccessibilityLabel(label)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: height)
    }
}

struct SidebarButton: NSViewRepresentable {
    let title: String
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func pressed(_ sender: NSButton) {action()}
    }
    func makeCoordinator() -> Coordinator {Coordinator()}
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        button.bezelStyle = .rounded;button.controlSize = .large;button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {button.title = title;context.coordinator.action = action}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 30)
    }
}

struct SidebarSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.padding(.horizontal, 8).frame(height: 34)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
        } else {
            content.padding(.horizontal, 8).frame(height: 34)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.25)))
        }
    }
}
extension View {
    func sidebarSurface() -> some View {modifier(SidebarSurface())}
}

// Preserve the existing right-pane content surface.
struct AxialContentSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 14)
                .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 14).fill(AxialAppearance.glassColor.opacity(0.12)))
        }
    }
}

struct AxialPanelSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.35), lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}
struct AxialGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label.font(.headline)
            configuration.content
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).modifier(AxialPanelSurface())
    }
}
struct AxialPopupSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(.horizontal, 8).frame(height: 28)
            .background(.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.4), lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}
extension View {
    func contentSurface() -> some View {modifier(AxialContentSurface())}
    func panelSurface() -> some View {modifier(AxialPanelSurface())}
    func popupSurface() -> some View {modifier(AxialPopupSurface())}
}

