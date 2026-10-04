# Reference previews

`approved-preview-2026-10-04.html` is the animated preview whose look was signed off before the in-game
code was written. It is self-contained (textures embedded), so open it in any browser to see how each
element is meant to look and move:

- **Frost**: diamond-cut ice rebuilt every cast from stacked cut layers; two cuts traced to the fill edge; a light glint sweeps across now and then.
- **Fire**: scrolling flames with embers rising.
- **Shadow**: black smoke with purple seams; dark wisps drift up.
- **Nature**: vines grow with the cast, twisting gently, with leaves and thorns.
- **Arcane**: rune circles at random heights and sizes, each rotating its own way; glyphs flare up.
- **Holy**: soft gold with four-point stars twinkling in and out.

The URL options work here too, for example `?style=framed&h=48&hold=70&only=frost,arcane`.

To see the current art instead, run `tools/Show-Preview.ps1`. It regenerates the textures and builds
the page from `tools/preview.html`. When a new look is approved, save the built page here under a new
date rather than replacing this one.
