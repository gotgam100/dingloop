import SwiftUI
import WidgetKit

@main
struct DingLoopLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DingLoopHomeWidget()
        DingLoopLiveActivityWidget()
        if #available(iOSApplicationExtension 26.0, *) {
            DingLoopAlarmKitWidget()
        }
    }
}
