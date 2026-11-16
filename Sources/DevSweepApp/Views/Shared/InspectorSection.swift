import SwiftUI

/// A part of what the inspector says, under its title: muted text that
/// wraps rather than truncates.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: self.title)
            self.content
                .font(.callout)
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
