# Fonts, served from this origin

IBM Plex Sans, IBM Plex Serif and IBM Plex Mono. Copyright 2017 IBM Corp. with
Reserved Font Name "Plex", licensed under the SIL Open Font License 1.1 — the
full text is in `OFL.txt` beside these files.

They are committed here rather than fetched at build time on purpose. A build
that reaches the network for a font is a build that can be handed a different
font, and the whole argument this site makes about itself is that nothing on it
comes from somebody else's server. These bytes were fetched once, by a person,
and they are in the diff.

The Latin subsets are the ones Google Fonts publishes; the files are IBM's,
under IBM's licence, and nothing on the page ever asks Google for them.

    plex-sans-var.woff2        variable, wght 100-700
    plex-sans-400-italic.woff2
    plex-serif-400.woff2
    plex-serif-600.woff2
    plex-mono-400.woff2
    plex-mono-500.woff2

The subset has no U+2192 (→) and no U+2713 (✓). That is not an oversight to fix
by loading a second font: arrows and ticks on this site are drawn as SVG, which
is sharper, colours with the text, and cannot fall back to whatever the
operating system feels like.
