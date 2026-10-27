# Album detail: scroll from panel to full screen

The detail's native vertical ScrollView reports its offset through the existing flip host. Over the first 160 pt the outer frame interpolates from the inset panel to the full screen (including safe areas). The rounded clipping and outside-tap exclusion follow the same frame. The top controls remain below the status bar.

At offsets 64–224 pt the panel's material navigation background fades in, and the compact artwork/title rises from below while fading in. Artwork is on the left of the album name. Returning to the top restores the panel frame and removes the compact title. No independent drag recognizer competes with scrolling.

Home's native navigation bar explicitly hides its background through 64 pt and shows it beyond that threshold. The pager applies this using only the selected album's offset, so off-screen pages cannot override it. Its compact title shares the panel's scroll-driven reveal, with a 16 pt upward movement and clipping to the title region. Reduce Motion keeps the opacity change without movement. Short native detail pages reserve at least 224 pt of scroll range so the title can finish appearing.

Only the selected album page reports expansion; horizontal browsing retains each page's offset. Cover Flow's `keepsSourceFrame` presentation retains its existing dimensions and reflection. The flip opening/closing animation is retained.

A minimum scroll range of 256 pt is reserved for the panel. Without it, increasing the viewport height caused UIKit to clamp the scroll offset and halt expansion halfway; this was reproduced and corrected during Simulator verification.

## Verified

- Debug iOS Simulator build succeeded: `/tmp/vinyl-panel-build.log`.
- Actual ScrollView offsets driven through a DEBUG fixture, with Simulator screenshots inspected: 80 pt (partially expanded), 240 pt (full screen and compact navigation), and 240 → 0 pt (restored inset panel and hidden compact title).
- The fixture uses in-memory albums and production `AlbumFlipPresentation` / `AlbumDetailView`.
- New/adjusted spacing follows 8/4 pt increments. Device safe-area values and interpolated geometry are dynamic.

## Reproduce

Xcode Preview: **Album panel expansion** in `HomeDesignPreview.swift`.
Debug launch arguments:

- `--album-panel-preview --panel-offset 80`
- `--album-panel-preview --panel-offset 240`
- `--album-panel-preview --panel-offset 240 --panel-return`

The return fixture scrolls to 240 pt after one second, then returns to zero two seconds later.

## Manual follow-up

Real-device drag/deceleration feel, Dynamic Type, horizontal album switching during expansion, editing, and dismissing from the full-screen state still need hands-on validation. The Simulator checks establish rendered endpoint/intermediate geometry, not physical gesture performance.

## Native header verification (2026-10-09)

- Debug Simulator build: `/tmp/vinyl-detail-header-build.log`.
- Existing isolated Home fixture: `--home-design-preview --home-open-album`, optionally with `--panel-offset 64`, `--panel-offset 144`, `--panel-offset 240`, or `--panel-offset 240 --panel-return`.
- Initial iOS 26.5 screenshots covered the top, threshold, 144 pt (partially visible title below its final position), 240 pt (fully visible title), and returning to zero. These verified the title but missed the system scroll edge effect that remained visible independently of toolbar background visibility; see the correction below.
- The first 240 pt check exposed clamping on the eight-track preview album: its content only allowed approximately 144 pt of scrolling and left the title half visible. The minimum native scroll range corrected this; the repeated 240 pt check shows the title fully visible.
- Screenshots: `/tmp/vinyl-detail-header-top.png`, `/tmp/vinyl-detail-header-threshold.png`, `/tmp/vinyl-detail-header-middle.png`, `/tmp/vinyl-detail-header-full.png`, and `/tmp/vinyl-detail-header-return.png`.
- Added dimensions use 8 pt increments. The title container uses a minimum height rather than a fixed height to accommodate larger text; large Dynamic Type and physical dragging still need manual confirmation.

## System scroll edge effect correction (2026-10-09)

The reported pale header with a sharp lower boundary was reproduced on iOS 27.0 using solid pink artwork. Hiding the toolbar background alone did not hide the independent system scroll edge effect. On iOS 26.5 the same effect appeared as a softer shaded region, which the earlier gradient-placeholder check missed.

`AlbumDetailView` now applies `scrollEdgeEffectHidden` to the pager hierarchy using the same selected-page threshold as the native toolbar background. Both remain hidden through 64 pt and become visible above it. The existing upward title reveal is retained.

- Final Debug Simulator build succeeded: `/tmp/vinyl-header-edge-build.log`; `git diff --check` passed.
- Actual initial geometry on iOS 27: `contentOffset=-116`, `topInset=116`, normalized `offset=0`.
- Inspected iOS 27 screenshots before/after at the top, at 64 pt (hidden), 240 pt (visible with the complete title), and 240 → 0 pt (hidden again). Also inspected the corrected top state on iOS 26.5.
- Before/after: `/tmp/vinyl-header-before-ios27.png`, `/tmp/vinyl-header-after-ios27.png`.
- Boundary/return: `/tmp/vinyl-header-edge-64.png`, `/tmp/vinyl-header-edge-240.png`, `/tmp/vinyl-header-edge-return.png`.
- iOS 26.5: `/tmp/vinyl-header-after-ios26.png`.
- Isolated reproduction: `--album-header-preview`, optionally adding `--panel-offset 64`, `--panel-offset 240`, or `--panel-offset 240 --panel-return`. This fixture logs actual scroll geometry and uses its own in-memory album; other preview datasets are unchanged.
- Xcode previews: **Album header — Light** and **Album header — Dark** in `HomeDesignPreview.swift`. Dark appearance and physical gesture feel remain manual follow-ups.

Apple documents the independent edge effect and its hiding API in [scrollEdgeEffectHidden](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)).
