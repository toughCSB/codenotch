# Provider marks

The SVG files in this directory come from the npm package `@lobehub/icons-static-svg` 1.95.0
(https://github.com/lobehub/lobe-icons, MIT License) and are unmodified:

| File | Original file in the package | Shown in |
|---|---|---|
| claude.svg | icons/claude.svg | unused monochrome alternative — the built-in mark is claude-color.svg |
| claude-color.svg | icons/claude-color.svg | Claude cell — Anthropic's official colour mark (`#D97757`) |
| codex.svg | icons/openai.svg | Codex cell (the OpenAI mark, matching upstream Codenotch's glyph choice) |
| codex-alt.svg | icons/codex.svg | alternative: Codex's own mark |
| cursor.svg | icons/cursor.svg | Cursor cell |
| gemini.svg | icons/antigravity.svg | unused monochrome alternative — the built-in mark is antigravity-color.svg |
| antigravity-color.svg | icons/antigravity-color.svg | Antigravity cell — Google's official four-colour mark |
| gemini-alt.svg | icons/gemini.svg | alternative: the Gemini spark |
| grok.svg | icons/grok.svg | Grok cell |
| opencode.svg | icons/opencode.svg | OpenCode cell |

Only Claude and Antigravity have an official colour variant in this package — OpenAI, Cursor, xAI
(Grok) and OpenCode all publish monochrome-only logos. OpenAI, Cursor and xAI's cells tint that
monochrome mark with a distinguishing accent colour chosen for this app (not an official brand
colour) — see `BRAND_TINT` in `ui/notch.html`. OpenCode's real mark is plain white, so its cell is
left untinted rather than inventing a colour it doesn't actually have.

MIT License — Copyright (c) LobeHub. See that repository's LICENSE.

**Trademarks**: these marks are trademarks of Anthropic, OpenAI, Anysphere (Cursor), Google, xAI
(Grok) and OpenCode respectively, and are used here only to identify the product whose usage is
displayed. Whether
they stay in a distributed build is the repository owner's call under each brand's guidelines;
they can be swapped for generated glyphs without touching any code.

**Overrides**: a file of the same name (`.svg` or `.png`) in `%APPDATA%\codenotch\glyphs\` takes
precedence over the built-in mark; it is picked up after "Refresh usage now" in the tray menu.
