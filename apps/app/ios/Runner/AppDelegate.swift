import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let externalRootsPlugin = ExternalRootsBridgePlugin()
  private let nativePdfPlugin = NativePdfBridgePlugin()
  private let nativeArchivePlugin = NativeArchiveBridgePlugin()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    externalRootsPlugin.register(with: engineBridge.applicationRegistrar.messenger())
    nativePdfPlugin.register(with: engineBridge.applicationRegistrar.messenger())
    nativeArchivePlugin.register(with: engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(
      name: "komganative/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "wakelock":
        let args = call.arguments as? [String: Any]
        let enabled = (args?["enabled"] as? Bool) ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = enabled
          result(nil)
        }
      case "eink":
        result(["isEink": false, "vendor": "apple"])
      case "saveImage":
        self?.handleSaveImage(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSaveImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let typedBytes = args["bytes"] as? FlutterStandardTypedData,
      !typedBytes.data.isEmpty
    else {
      result(FlutterError(code: "IO_ERROR", message: "Empty image bytes", details: nil))
      return
    }
    let rawName = (args["fileName"] as? String) ?? "yomu-page.png"
    let cleanName = (rawName as NSString).lastPathComponent
    let fileName = cleanName.isEmpty ? "yomu-page.png" : cleanName
    let imageData = typedBytes.data

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "PERMISSION_DENIED",
              message: "Photo library add permission denied",
              details: nil
            )
          )
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = fileName
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: imageData, options: options)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result(["location": "Photos"])
          } else {
            result(
              FlutterError(
                code: "IO_ERROR",
                message: error?.localizedDescription ?? "Failed to save image",
                details: nil
              )
            )
          }
        }
      }
    }
  }
}
