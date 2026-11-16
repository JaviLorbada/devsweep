import SwiftUI

extension View {
    /// What VoiceOver says for this element: the text's label, then its value.
    func spoken(_ text: SpokenText) -> some View {
        self.accessibilityLabel(text.label).accessibilityValue(text.value)
    }
}
