import Flutter
import PDFKit
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

/// iOS 原生 `PDFKit` 按需光栅化、大纲解析与密码解锁插件（LMB-11）。
final class NativePdfBridgePlugin: NSObject {
  private let queue = DispatchQueue(label: "dev.yomu.native_pdf", qos: .userInitiated)
  private var cache: [String: PDFDocument] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yomu/native_pdf",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "inspect":
      guard let filePath = args?["filePath"] as? String, !filePath.isEmpty else {
        result(FlutterError(code: "IO_ERROR", message: "Missing filePath", details: nil))
        return
      }
      let password = args?["password"] as? String
      queue.async { [weak self] in
        guard let self = self else { return }
        switch self.openDocument(path: filePath, password: password) {
        case .failure(let err):
          DispatchQueue.main.async { result(err) }
        case .success(let doc):
          var pages: [[String: Any]] = []
          for idx in 0..<doc.pageCount {
            let bounds = doc.page(at: idx)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 800, height: 1200)
            pages.append([
              "pageNumber": idx + 1,
              "width": max(1, Int(bounds.width.rounded())),
              "height": max(1, Int(bounds.height.rounded())),
            ])
          }
          var outline: [[String: Any]] = []
          if let root = doc.outlineRoot {
            Self.collectOutline(node: root, in: doc, into: &outline)
          }
          let attrs = doc.documentAttributes
          let title = attrs?[PDFDocumentAttribute.titleAttribute] as? String
          let author = attrs?[PDFDocumentAttribute.authorAttribute] as? String
          var payload: [String: Any] = [
            "pageCount": doc.pageCount,
            "pages": pages,
            "outline": outline,
          ]
          if let title = title, !title.isEmpty { payload["title"] = title }
          if let author = author, !author.isEmpty { payload["author"] = author }
          DispatchQueue.main.async { result(payload) }
        }
      }
    case "renderPage":
      guard let filePath = args?["filePath"] as? String, !filePath.isEmpty else {
        result(FlutterError(code: "IO_ERROR", message: "Missing filePath", details: nil))
        return
      }
      let pageNumber = (args?["pageNumber"] as? Int) ?? 1
      let targetWidth = max(240, min(3200, (args?["targetWidthPx"] as? Int) ?? 1600))
      let password = args?["password"] as? String
      queue.async { [weak self] in
        guard let self = self else { return }
        switch self.openDocument(path: filePath, password: password) {
        case .failure(let err):
          DispatchQueue.main.async { result(err) }
        case .success(let doc):
          let idx = max(0, min(doc.pageCount - 1, pageNumber - 1))
          guard let page = doc.page(at: idx) else {
            DispatchQueue.main.async {
              result(FlutterError(code: "IO_ERROR", message: "Page out of range", details: nil))
            }
            return
          }
          let bounds = page.bounds(for: .mediaBox)
          let safeW = max(1.0, bounds.width)
          let safeH = max(1.0, bounds.height)
          let scale = CGFloat(targetWidth) / safeW
          let size = CGSize(width: CGFloat(targetWidth), height: max(1.0, min(6400.0, safeH * scale)))
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1.0
          format.opaque = true
          let renderer = UIGraphicsImageRenderer(size: size, format: format)
          let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
          }
          guard let data = image.pngData() else {
            DispatchQueue.main.async {
              result(FlutterError(code: "IO_ERROR", message: "Failed to encode PNG", details: nil))
            }
            return
          }
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
        }
      }
    case "closeDocument":
      if let filePath = args?["filePath"] as? String {
        queue.async { [weak self] in
          self?.cache.removeValue(forKey: filePath)
        }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private enum OpenOutcome {
    case success(PDFDocument)
    case failure(FlutterError)
  }

  private func openDocument(path: String, password: String?) -> OpenOutcome {
    if let existing = cache[path], !existing.isLocked {
      return .success(existing)
    }
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
      return .failure(FlutterError(code: "CORRUPTED", message: "Unable to open PDF", details: nil))
    }
    if doc.isLocked {
      guard let pwd = password, !pwd.isEmpty, doc.unlock(withPassword: pwd) else {
        return .failure(FlutterError(code: "INVALID_PASSWORD", message: "Password required", details: nil))
      }
    }
    if cache.count >= 2, let firstKey = cache.keys.first {
      cache.removeValue(forKey: firstKey)
    }
    cache[path] = doc
    return .success(doc)
  }

  private static func collectOutline(
    node: PDFOutline,
    in doc: PDFDocument,
    into out: inout [[String: Any]]
  ) {
    for i in 0..<node.numberOfChildren {
      guard let child = node.child(at: i) else { continue }
      if let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines),
         !label.isEmpty,
         let page = child.destination?.page {
        let idx = doc.index(for: page)
        if idx != NSNotFound {
          out.append(["title": label, "startPage": idx + 1])
        }
      }
      collectOutline(node: child, in: doc, into: &out)
    }
  }
}
