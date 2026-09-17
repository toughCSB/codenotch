import XCTest

/// The catalog's source language is English. A missing translation in any
/// other language must fall back to that English, not fail the suite — the
/// app's language is English, and a half-finished locale must not block CI.
final class CatalogCoverageTests: XCTestCase {
    func testSourceLanguageIsEnglish() throws {
        XCTAssertEqual(try loadCatalog().json.sourceLanguage, "en")
    }

    func testTheCatalogHasKeys() throws {
        XCTAssertFalse(try loadCatalog().json.strings.isEmpty, "catalog has no strings")
    }

    func testCatalogHasNoMergeConflictMarkers() throws {
        XCTAssertFalse(
            try loadCatalog().raw.contains("<<<<<<"),
            "Localizable.xcstrings still has a leftover conflict marker"
        )
    }

    func testRussianCoreCopyIsTranslated() throws {
        let catalog = try loadCatalog().json
        let expected = [
            "just now": "только что",
            "Resets in %lld min": "Сброс через %lld мин",
            "%lld%% Used · %lld%% left": "Использовано %lld%% · осталось %lld%%",
            "Always show": "Всегда показывать",
            "Settings…": "Настройки…",
            "Sign in to %@": "Войти в %@",
            "%lld%% of its %@ limit used.": "Использовано %lld%% от лимита «%@»."
        ]

        for (key, value) in expected {
            XCTAssertEqual(
                catalog.strings[key]?.localizations?["ru"]?.stringUnit?.value,
                value,
                "missing Russian translation for \(key)"
            )
        }
    }

    func testUkrainianCoreCopyIsTranslated() throws {
        let catalog = try loadCatalog().json
        let expected = [
            "just now": "щойно",
            "Resets in %lld min": "Скидання через %lld хв",
            "%lld%% Used · %lld%% left": "Використано %lld%% · лишилось %lld%%",
            "Always show": "Показувати завжди",
            "Settings…": "Налаштування…",
            "Sign in to %@": "Увійти в %@",
            "%lld%% of its %@ limit used.": "Використано %lld%% ліміту «%@»."
        ]

        for (key, value) in expected {
            XCTAssertEqual(
                catalog.strings[key]?.localizations?["uk"]?.stringUnit?.value,
                value,
                "missing Ukrainian translation for \(key)"
            )
        }
    }

    /// Korean is a language of the person this app is for, and it is served from
    /// the same catalog as every other one. Spot-checked rather than counted, for
    /// the reason spelled out below: a completeness test passes only until the
    /// next string is added, and then blocks the change that adds it.
    func testKoreanCoreCopyIsTranslated() throws {
        let catalog = try loadCatalog().json
        let expected = [
            "just now": "방금 전",
            "Resets in %lld min": "%lld분 후 재설정",
            "%lld%% Used · %lld%% left": "%lld%% 사용 · %lld%% 남음",
            "Always show": "항상 표시",
            "Settings…": "설정…",
            "Sign in to %@": "%@에 로그인",
            "%lld%% of its %@ limit used.": "%lld%% 사용 · %@ 한도"
        ]

        for (key, value) in expected {
            XCTAssertEqual(
                catalog.strings[key]?.localizations?["ko"]?.stringUnit?.value,
                value,
                "missing Korean translation for \(key)"
            )
        }
    }

    /// A placeholder and a bare percent sign cannot live in the same string.
    ///
    /// `String(localized:)` applies the entry as a format once there is an
    /// argument to substitute, and a stray `%` — "80% and" reads as the
    /// conversion `% a` — makes the whole entry unloadable. The app then shows
    /// the English source instead, in *every* language, silently, and only for
    /// that one string. Three of them sat in here doing exactly that. A percent
    /// sign next to a placeholder has to be written `%%`.
    func testNoEntryMixesAPlaceholderWithABarePercent() throws {
        let catalog = try loadCatalog().json
        let placeholder = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[0-9.]*[a-zA-Z@]")

        func mixesThem(_ text: String) -> Bool {
            // `%%` is a literal percent sign, so it is neither a placeholder nor
            // a bare one. This is where the three bad strings were found.
            let undoubled = text.replacingOccurrences(of: "%%", with: "")
            let range = NSRange(undoubled.startIndex..., in: undoubled)
            guard placeholder.firstMatch(in: undoubled, range: range) != nil else { return false }
            let withoutPlaceholders = placeholder.stringByReplacingMatches(
                in: undoubled, range: range, withTemplate: ""
            )
            return withoutPlaceholders.contains("%")
        }

        for (key, entry) in catalog.strings {
            XCTAssertFalse(mixesThem(key),
                           "the source for \(key) mixes a placeholder with a bare percent")
            for (language, localization) in entry.localizations ?? [:] {
                guard let value = localization.stringUnit?.value else { continue }
                XCTAssertFalse(mixesThem(value),
                               "\(language) copy for \(key) mixes a placeholder with a bare percent")
            }
        }
    }

    /// Every Korean entry has to keep the placeholders the English source has.
    /// A translation that drops one is not a wording preference — it prints a
    /// number the reader was promised nowhere, or swallows one they were.
    func testEveryKoreanEntryKeepsItsPlaceholders() throws {
        let catalog = try loadCatalog().json
        let placeholders = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[0-9.]*[a-zA-Z@]")

        func found(in text: String) -> [String] {
            // `%%` is a literal percent sign, not a placeholder, and the source
            // strings use it — "12% used · 88% left" among them.
            let text = text.replacingOccurrences(of: "%%", with: "")
            let range = NSRange(text.startIndex..., in: text)
            return placeholders.matches(in: text, range: range).map {
                String(text[Range($0.range, in: text)!])
            }
        }

        var checked = 0
        for (key, entry) in catalog.strings {
            guard let value = entry.localizations?["ko"]?.stringUnit?.value else { continue }
            checked += 1
            XCTAssertEqual(found(in: value).sorted(), found(in: key).sorted(),
                           "Korean copy for \(key) does not carry the same placeholders")
        }
        XCTAssertGreaterThan(checked, 500, "the Korean localization looks unbuilt")
    }

    /// There is deliberately no "language X covers every key" test.
    ///
    /// The rule at the top of this file is that a missing translation falls
    /// back to English rather than failing the suite, and no locale here is
    /// complete: French and Portuguese cover 350 of 470 keys, Japanese 428.
    /// #141 added one for Russian, which passed only while Russian happened to
    /// be complete — the next pull request to add a string broke it, and that
    /// is exactly the CI block the rule exists to prevent.

    // MARK: - Loading

    /// Repo `Tests/`, so the catalog is `../Sources/Localizable.xcstrings`.
    private func catalogURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Sources/Localizable.xcstrings")
            .standardizedFileURL
    }

    private func loadCatalog() throws -> (raw: String, json: CatalogFile) {
        let url = catalogURL()
        do {
            let data = try Data(contentsOf: url)
            return (String(decoding: data, as: UTF8.self), try JSONDecoder().decode(CatalogFile.self, from: data))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw XCTSkip("macOS privacy restricts reading the source catalog at \(url.path)")
        }
    }
}

private struct CatalogFile: Decodable {
    var sourceLanguage: String
    var strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {
    var localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    var stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    var state: String?
    var value: String?
}
