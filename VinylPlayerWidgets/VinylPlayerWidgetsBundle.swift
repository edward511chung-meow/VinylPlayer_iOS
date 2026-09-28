import SwiftUI
import WidgetKit

@main
struct VinylPlayerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingTiltedWidget()
        NowPlayingRippleWidget()
        NowPlayingLiveActivity()
    }
}
