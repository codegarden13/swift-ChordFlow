import AppKit
import CoreText
import SwiftUI

enum ChordflowDesign {
    private static let cartographHeadingFontIsRegistered: Bool = {
        let nestedURL = Bundle.module.url(
            forResource: "quicksand-700-normal",
            withExtension: "woff2",
            subdirectory: "Fonts"
        )
        guard let url = nestedURL ?? Bundle.module.url(forResource: "quicksand-700-normal", withExtension: "woff2") else {
            NSLog("Chordflow: Quicksand-Ressource fehlt; verwende die Systemschrift.")
            return false
        }
        var registrationError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
        if !registered, let error = registrationError?.takeRetainedValue() {
            NSLog("Chordflow: Quicksand konnte nicht registriert werden: %@", String(describing: error))
        }
        return registered
    }()

    /// Cartograph uses Quicksand 700 for its large web-export headings.
    /// macOS falls back to its rounded system face if Quicksand is unavailable.
    static func heading(_ style: Font.TextStyle = .title2, size: CGFloat? = nil) -> Font {
        if cartographHeadingFontIsRegistered, let size, NSFont(name: "Quicksand", size: size) != nil {
            return .custom("Quicksand", size: size, relativeTo: style).weight(.bold)
        }
        return .system(style, design: .rounded).weight(.bold)
    }

    // Bedienfarbe und musikalische Bedeutungsfarben bleiben bewusst getrennt.
    static let actionTeal = Color(red: 0.05, green: 0.43, blue: 0.42)
    static let chordToneBlue = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let inversionPurple = Color(red: 0.69, green: 0.28, blue: 0.86)
    static let alteredPink = Color(red: 0.95, green: 0.20, blue: 0.43)
    static let tensionOrange = Color(red: 0.96, green: 0.49, blue: 0.10)
    static let commonMint = Color(red: 0.12, green: 0.66, blue: 0.43)
    static let resolutionGold = Color(red: 0.78, green: 0.57, blue: 0.08)
    static let focusGreen = Color(red: 0.22, green: 0.94, blue: 0.48)
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
}
