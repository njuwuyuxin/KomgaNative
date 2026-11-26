import Flutter
import UIKit
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate {

}

/// iOS 外部目录 Security-Scoped Bookmark 持久化、iCloud 占位感知与零拷贝随机读桥接（LMB-08）。
final class ExternalRootsBridgePlugin: NSObject, UIDocumentPickerDelegate {
  private var pendingPickResult: FlutterResult?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yomu/external_roots",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "pickDirectory":
      DispatchQueue.main.async { [weak self] in
        self?.presentFolderPicker(result: result)
      }
    case "listTree":
      guard let bookmarkB64 = args?["uriOrBookmark"] as? String else {
        result([])
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let items = Self.listTree(bookmarkBase64: bookmarkB64)
        DispatchQueue.main.async { result(items) }
      }
    case "checkPermission":
      guard let bookmarkB64 = args?["uriOrBookmark"] as? String else {
        result(false)
        return
      }
      result(Self.resolveBookmark(bookmarkB64) != nil)
    case "ensureNomedia":
      // iOS 相册不扫描 Files 目录，直接返回 true。
      result(true)
    case "fileLength":
      guard let path = args?["uri"] as? String else {
        result(nil)
        return
      }
      let rootB64 = args?["rootUriOrBookmark"] as? String
      DispatchQueue.global(qos: .userInitiated).async {
        let len = Self.withResolvedRoot(rootB64) {
          let attrs = try? FileManager.default.attributesOfItem(atPath: path)
          return (attrs?[.size] as? NSNumber)?.int64Value
        }
        DispatchQueue.main.async { result(len) }
      }
    case "readFileRange":
      guard
        let path = args?["uri"] as? String,
        let offset = (args?["offset"] as? NSNumber)?.uint64Value,
        let length = (args?["length"] as? NSNumber)?.intValue
      else {
        result(nil)
        return
      }
      let rootB64 = args?["rootUriOrBookmark"] as? String
      DispatchQueue.global(qos: .userInitiated).async {
        let data: Data? = Self.withResolvedRoot(rootB64) {
          guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
          defer { try? fh.close() }
          do {
            try fh.seek(toOffset: offset)
            return try fh.read(upToCount: length) ?? Data()
          } catch {
            return nil
          }
        }
        DispatchQueue.main.async {
          if let data = data {
            result(FlutterStandardTypedData(bytes: data))
          } else {
            result(nil)
          }
        }
      }
    case "triggerCloudDownload":
      guard let path = args?["uri"] as? String else {
        result(false)
        return
      }
      let rootB64 = args?["rootUriOrBookmark"] as? String
      DispatchQueue.global(qos: .utility).async {
        let ok: Bool = Self.withResolvedRoot(rootB64) {
          do {
            try FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
            return true
          } catch {
            return false
          }
        } ?? false
        DispatchQueue.main.async { result(ok) }
      }
    case "releasePermission":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentFolderPicker(result: @escaping FlutterResult) {
    guard pendingPickResult == nil else {
      result(nil)
      return
    }
    guard let presenter = Self.topViewController() else {
      result(nil)
      return
    }
    pendingPickResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let callback = pendingPickResult else { return }
    pendingPickResult = nil
    guard let url = urls.first else {
      callback(nil)
      return
    }
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try url.bookmarkData(
        options: .minimalBookmark,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      callback([
        "uriOrBookmark": bookmark.base64EncodedString(),
        "displayName": url.lastPathComponent,
        "kind": "iosBookmark",
        "hasNomedia": true,
      ])
    } catch {
      callback(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let callback = pendingPickResult
    pendingPickResult = nil
    callback?(nil)
  }

  private static func resolveBookmark(_ base64: String) -> URL? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    var stale = false
    return try? URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
  }

  private static func withResolvedRoot<T>(_ rootB64: String?, body: () -> T?) -> T? {
    if let b64 = rootB64, let rootUrl = resolveBookmark(b64) {
      let started = rootUrl.startAccessingSecurityScopedResource()
      defer { if started { rootUrl.stopAccessingSecurityScopedResource() } }
      return body()
    }
    return body()
  }

  private static func listTree(bookmarkBase64: String) -> [[String: Any]] {
    guard let rootUrl = resolveBookmark(bookmarkBase64) else { return [] }
    let started = rootUrl.startAccessingSecurityScopedResource()
    defer { if started { rootUrl.stopAccessingSecurityScopedResource() } }

    let rootPath = rootUrl.path.hasSuffix("/") ? rootUrl.path : rootUrl.path + "/"
    let keys: [URLResourceKey] = [
      .isDirectoryKey,
      .fileSizeKey,
      .contentModificationDateKey,
      .ubiquitousItemDownloadingStatusKey,
    ]
    guard let enumerator = FileManager.default.enumerator(
      at: rootUrl,
      includingPropertiesForKeys: keys,
      options: [.skipsPackageDescendants]
    ) else { return [] }

    var out: [[String: Any]] = []
    for case let itemUrl as URL in enumerator {
      let name = itemUrl.lastPathComponent
      let isIcloudStub = name.hasPrefix(".") && name.hasSuffix(".icloud")
      if !isIcloudStub && name.hasPrefix(".") { continue }

      let values = try? itemUrl.resourceValues(forKeys: Set(keys))
      let isDir = values?.isDirectory ?? false
      let size = Int64(values?.fileSize ?? 0)
      let mtimeMs = Int64((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
      let dlStatus = values?.ubiquitousItemDownloadingStatus
      let isCloudPlaceholder = isIcloudStub || (dlStatus == .notDownloaded)

      let fullPath = itemUrl.path
      let relRaw = fullPath.hasPrefix(rootPath) ? String(fullPath.dropFirst(rootPath.count)) : name
      let logicalName: String
      let logicalRel: String
      if isIcloudStub {
        let stripped = String(name.dropFirst().dropLast(".icloud".count))
        logicalName = stripped
        let parent = (relRaw as NSString).deletingLastPathComponent
        logicalRel = parent.isEmpty ? stripped : "\(parent)/\(stripped)"
      } else {
        logicalName = name
        logicalRel = relRaw
      }

      out.append([
        "uri": itemUrl.path,
        "relativePath": logicalRel,
        "name": logicalName,
        "isDirectory": isDir,
        "sizeBytes": size,
        "lastModifiedMs": mtimeMs,
        "isCloudPlaceholder": isCloudPlaceholder,
      ])
    }
    return out
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
