import DevCleanKit
import SwiftUI

/// Placeholder screens until milestone 4.
struct XcodeVersionsView: View {
    var body: some View {
        ContentUnavailableView("Xcode versions", systemImage: "hammer", description: Text("This screen arrives in a later milestone."))
    }
}

struct SimulatorRuntimesView: View {
    var body: some View {
        ContentUnavailableView("Simulator runtimes", systemImage: "iphone", description: Text("This screen arrives in a later milestone."))
    }
}

struct XcodesContent: View {
    var body: some View { XcodeVersionsView() }
}

struct RuntimesContent: View {
    var body: some View { SimulatorRuntimesView() }
}

struct XcodeInspector: View {
    var body: some View { EmptyView() }
}

struct RuntimeInspector: View {
    var body: some View { EmptyView() }
}
