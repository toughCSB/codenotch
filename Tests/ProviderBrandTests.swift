import AppKit
import SwiftUI
import XCTest
@testable import ProviderMonitor

/// The colour each provider's mark is drawn in.
///
/// The table makes two different promises and these cover them separately: a
/// colour the vendor publishes for the mark, and an accent this app chose
/// because the vendor publishes only a monochrome logo. The second group is the
/// one that could quietly start looking official, so it is pinned to the exact
/// three accents the Windows port uses — a provider is meant to look the same on
/// both, and neither build should drift into inventing a brand colour.
final class ProviderBrandTests: XCTestCase {

    private func rgb(_ glyph: ProviderGlyph) -> (Int, Int, Int)? {
        guard let colour = ProviderBrand.markColor(glyph),
              let ns = NSColor(colour).usingColorSpace(.sRGB) else { return nil }
        return (Int((ns.redComponent * 255).rounded()),
                Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent * 255).rounded()))
    }

    /// Compared apart rather than as a tuple: an optional tuple is not
    /// `Equatable`, so `XCTAssertEqual` cannot take it.
    private func assertColour(_ glyph: ProviderGlyph, is hex: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let got = rgb(glyph) else {
            XCTFail("\(glyph) has no colour", file: file, line: line)
            return
        }
        let want = ((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF)
        XCTAssertEqual(got.0, want.0, "\(glyph) red", file: file, line: line)
        XCTAssertEqual(got.1, want.1, "\(glyph) green", file: file, line: line)
        XCTAssertEqual(got.2, want.2, "\(glyph) blue", file: file, line: line)
    }

    func testClaudeWearsAnthropicsOwnColour() {
        assertColour(.claude, is: 0xD97757)
    }

    func testTheVendorsOwnColoursAreTheOnesTheyPublish() {
        assertColour(.deepseek, is: 0x4D6BFE)
        assertColour(.qwen, is: 0x615CED)
        assertColour(.mistral, is: 0xFA520F)
        assertColour(.meta, is: 0x0866FF)
        assertColour(.geminiSpark, is: 0x4285F4)
    }

    /// Monochrome-only logos. These are accents, not brand colours — the comment
    /// above says so, and this is what keeps the two from being confused later.
    func testTheHouseAccentsAreTheOnesTheWindowsPortUses() {
        assertColour(.openai, is: 0x10A37F)
        assertColour(.cursor, is: 0x3B82F6)
        assertColour(.grok, is: 0x8B5CF6)
    }

    /// A white mark tinted with something is no longer the mark the vendor
    /// publishes, so these keep the app's own text colour.
    func testMarksThatAreAlreadyWhiteAreLeftAlone() {
        XCTAssertNil(ProviderBrand.markColor(.opencode))
        XCTAssertNil(ProviderBrand.markColor(.ollama))
        XCTAssertNil(ProviderBrand.markColor(.ollamaLocal))
        XCTAssertNil(ProviderBrand.markColor(.lmstudio))
    }

    func testAntigravityIsTheOnlyMarkBundledInItsOwnColours() {
        XCTAssertTrue(ProviderBrand.isFullColourMark(.antigravity))
        for glyph in [ProviderGlyph.claude, .openai, .cursor, .grok, .geminiSpark,
                      .opencode, .ollama, .lmstudio, .deepseek, .qwen] {
            XCTAssertFalse(ProviderBrand.isFullColourMark(glyph), "\(glyph) is not artwork")
        }
    }

    /// Artwork keeps its own colours, so it must never also carry a tint — the
    /// view applies one only when the table gives a colour.
    func testArtworkCarriesNoTint() {
        XCTAssertNil(ProviderBrand.markColor(.antigravity))
    }
}
