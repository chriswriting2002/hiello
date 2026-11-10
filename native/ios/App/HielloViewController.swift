import UIKit
import Capacitor

/// Hiello's own copy of Capacitor's screen, so it can register the widget bridge (HielloWidget) with the web app.
class HielloViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(HielloWidgetPlugin())
    }
}
