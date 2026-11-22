import SwiftUI

// The Simulators screen: every simulator and the space its data takes.
// DevSweep lists them; it never erases or deletes one.

struct SimulatorsView: View {
    var body: some View {
        ScrollView { SimulatorsContent() }
    }
}
