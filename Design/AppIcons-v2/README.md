# Updated Vinyl Player icons

Final layout follows the user's latest turntable reference: top-left cropped tonearm pivot, diagonal arm and two-screw headshell, selectors on the lower-left wooden margin, and a clean right-hand wood wedge.

- `final/`: 21 1024×1024 appearance assets and the three named standalone exports.
- `review.png`: light, dark and transparent variants side by side.
- `render_variants.py`: reproducible palette, alpha and size processing. Run with Python, Pillow and NumPy from the project root.
- `generation.json`: built-in image_gen prompts, source paths and final-master provenance.
- `generated/AppIcon_light.png`: final master; other generated files are discarded material explorations, not installed assets.
- `original-assets/`: original asset catalogs backed up before replacement.

Creation: built-in image_gen generated and corrected the master. The user explicitly authorized deterministic programmatic recoloring, background extraction and sizing. All installed variants use this same final master, preserving hardware positions. Light/dark icons are opaque RGB; tinted foregrounds preserve RGBA transparency. Existing asset names and alternate-icon identifiers remain unchanged.

Named exports:
- `final/vinyl_player_light_app_icon.png`
- `final/vinyl_player_dark_app_icon.png`
- `final/vinylplayer_light_icon_transparent.png`
