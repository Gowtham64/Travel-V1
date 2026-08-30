import WidgetKit
import SwiftUI

/// Entry point for the VoyplanTripActivity widget extension.
@main
struct VoyplanTripActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            VoyplanTripActivityLiveActivity()
        }
    }
}
