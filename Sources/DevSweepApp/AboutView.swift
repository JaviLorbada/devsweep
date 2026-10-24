import AppKit
import DevSweepKit
import SwiftUI

/// The About window: the icon, the name and version, who made it, the
/// repository and license, and what it builds on.
struct AboutView: View {
    static let author = "Javi Lorbada"
    static let website = URL(string: "https://javilorbada.com")!

    var body: some View {
        VStack(spacing: 16) {
            // The bundle's icon, so artwork that replaces the drawn one shows here too.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(ProductInfo.name)
                    .font(.title.weight(.semibold))
                Text("Version \(ProductInfo.version) (\(ProductInfo.build))")
                    .font(.callout)
                    .foregroundStyle(.muted)
                    .textSelection(.enabled)
            }
            Link("Made by \(Self.author)", destination: Self.website)
            HStack(spacing: 18) {
                Link("Source on GitHub", destination: ProductInfo.repository)
                Link("MIT License", destination: ProductInfo.license)
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Acknowledgements")
                Acknowledgement(
                    name: "swift-argument-parser",
                    note: "Reads the command line tool's options.",
                    links: [
                        (
                            "Apache License 2.0",
                            URL(string: "https://github.com/apple/swift-argument-parser/blob/main/LICENSE.txt")!),
                        ("Source", URL(string: "https://github.com/apple/swift-argument-parser")!),
                    ])
                Acknowledgement(
                    name: "devclean",
                    note: "The bash script in \(Self.author)'s dotfiles that the command line tool grew "
                        + "from, and still matches word for word.",
                    links: [("Source", URL(string: "https://github.com/JaviLorbada/dotfiles")!)])
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Copyright © 2026 \(Self.author)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 380)
    }
}

/// One thing the project builds on: its name, what it does here, and links.
private struct Acknowledgement: View {
    let name: String
    let note: String
    let links: [(title: String, url: URL)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.name).fontWeight(.semibold)
            Text(self.note)
                .font(.callout)
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                ForEach(self.links, id: \.title) { link in
                    Link(link.title, destination: link.url)
                }
            }
            .font(.callout)
        }
    }
}
