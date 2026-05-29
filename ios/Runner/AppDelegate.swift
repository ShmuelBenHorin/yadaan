import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ─── iCloud Key-Value Store channel ─────────────────────────────────────
    let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "ICloudKVPlugin")!.messenger()
    let kvChannel = FlutterMethodChannel(name: "icloud_kv",
                                         binaryMessenger: messenger)
    kvChannel.setMethodCallHandler { call, result in
      let store = NSUbiquitousKeyValueStore.default
      switch call.method {
      case "writeAll":
        guard let dict = call.arguments as? [String: Any] else {
          result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
          return
        }
        for (key, value) in dict { store.set(value, forKey: key) }
        store.synchronize()
        result(nil)
      case "readAll":
        store.synchronize()
        result(store.dictionaryRepresentation)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
