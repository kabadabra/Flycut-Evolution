import SwiftUI
import FlycutCore
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Flycut Evolution").font(.largeTitle)
            Text("Version \(FlycutVersion.current)").foregroundStyle(.secondary)
            Text("Maintained by Emerging Dynamics")
            Text("A fork of TermiT/Flycut and Jumpcut\nFree and open source · MIT license").multilineTextAlignment(.center)
            Link("Flycut source and contributors", destination: URL(string: "https://github.com/kabadabra/Flycut")!)
            Link("Upstream TermiT/Flycut", destination: URL(string: "https://github.com/TermiT/Flycut")!)
            Text("Cloud sync is not available in this release.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
