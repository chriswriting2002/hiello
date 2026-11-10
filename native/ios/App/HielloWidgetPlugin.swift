import Foundation
import UIKit
import Capacitor
import WidgetKit

/// Lets the web app hand the home screen widget what it needs:
/// the family connection (so the widget can fetch new photos by itself) and the newest pictures (so it updates instantly).
@objc(HielloWidgetPlugin)
public class HielloWidgetPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HielloWidgetPlugin"
    public let jsName = "HielloWidget"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "save", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "reload", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setIcon", returnType: CAPPluginReturnPromise)
    ]
    static let group = "group.com.hiello.family"

    @objc func save(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else { call.reject("missing json"); return }
        UserDefaults(suiteName: HielloWidgetPlugin.group)?.set(json, forKey: "hiello.config")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    @objc func saveFile(_ call: CAPPluginCall) {
        guard let name = call.getString("name"),
              let b64 = call.getString("base64"),
              let data = Data(base64Encoded: b64),
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HielloWidgetPlugin.group) else {
            call.reject("could not save file"); return
        }
        let safe = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        do {
            try data.write(to: dir.appendingPathComponent(safe), options: .atomic)
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func reload(_ call: CAPPluginCall) {
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    /// Switch the home screen icon. name: "Pink", "Cream", "Classic", or empty for the standard graphite icon.
    @objc func setIcon(_ call: CAPPluginCall) {
        let raw = call.getString("name") ?? ""
        let name: String? = raw.isEmpty ? nil : raw
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { call.reject("not supported"); return }
            UIApplication.shared.setAlternateIconName(name) { error in
                if let error = error { call.reject(error.localizedDescription) } else { call.resolve() }
            }
        }
    }
}
