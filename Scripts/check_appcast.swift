// Checks an appcast the way every installed DevSweep will: that its one
// update is the zip, at its length, with an EdDSA signature that verifies
// against the public key the app trusts. An appcast signed with any other
// key would offer an update that every copy refuses.
//
// Usage: swift Scripts/check_appcast.swift <appcast.xml> <zip> <public key>

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("check_appcast.swift: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("usage: swift Scripts/check_appcast.swift <appcast.xml> <zip> <public key>")
}

let zip = URL(fileURLWithPath: arguments[2])
guard let appcast = try? XMLDocument(contentsOf: URL(fileURLWithPath: arguments[1])),
      let enclosures = try? appcast.nodes(forXPath: "/rss/channel/item/enclosure") as? [XMLElement]
else { fail("can't read \(arguments[1])") }
guard enclosures.count == 1, let enclosure = enclosures.first else {
    fail("the appcast has \(enclosures.count) updates, not one")
}

guard let data = try? Data(contentsOf: zip) else { fail("can't read \(zip.path)") }

let url = enclosure.attribute(forName: "url")?.stringValue ?? ""
guard url.hasSuffix("/" + zip.lastPathComponent) else {
    fail("the update is \(url), not \(zip.lastPathComponent)")
}

guard enclosure.attribute(forName: "length")?.stringValue == String(data.count) else {
    fail("the update's length isn't the zip's, \(data.count) bytes")
}

guard let signature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue
    .flatMap({ Data(base64Encoded: $0) })
else {
    fail("the update has no EdDSA signature; generate_appcast leaves it out when the private key isn't the one "
        + "whose public half is the app's SUPublicEDKey")
}

guard let key = Data(base64Encoded: arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key)
else { fail("\(arguments[3]) isn't an Ed25519 public key") }
guard publicKey.isValidSignature(signature, for: data) else {
    fail("the update's signature doesn't verify with the app's public key; is the private key the right one?")
}

let version = enclosure.parent.flatMap { ($0 as? XMLElement)?.elements(forName: "sparkle:version").first }?
    .stringValue ?? "?"
print("\(url): build \(version), \(data.count) bytes, signed with the key the app trusts")
