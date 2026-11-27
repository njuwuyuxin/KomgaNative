/// 远程漫画服务器地址（值对象）。
///
/// 解析用户输入并做规范化：补协议、去尾斜杠、保留子路径（如反代部署的 `https://host/comics`）。
/// 校验放在领域层而不是 UI 层，这样 router / 连接页 / 设置页共用同一套规则。

/// 服务器地址解析失败的结构化原因（UI 按需按当前 Locale 映射提示文案，不在领域层硬编码界面文本）。
enum ServerAddressError {
  empty,
  containsWhitespace,
  invalidSyntax,
  unsupportedScheme,
  missingHost,
}

/// 携带结构化 [reason] 的地址格式异常（继承 [FormatException] 保持兼容）。
final class ServerAddressFormatException extends FormatException {
  const ServerAddressFormatException(this.reason, [super.message = '']);

  final ServerAddressError reason;
}

class ServerAddress {
  const ServerAddress._(this.uri);

  final Uri uri;

  /// 不含结尾斜杠的规范化基址。
  String get baseUrl => uri.toString();

  String get host => uri.host;
  int? get port => uri.hasPort ? uri.port : null;
  bool get isHttps => uri.scheme == 'https';
  bool get isLoopback =>
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

  /// 宽松解析：用户只输入 `192.168.1.10:25600` 也接受（默认补 https）。
  ///
  /// 抛 [ServerAddressFormatException]（继承自 [FormatException]）。
  static ServerAddress parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const ServerAddressFormatException(
        ServerAddressError.empty,
        'empty',
      );
    }
    // `Uri.parse` 会把空格百分号编码进 host（`not a url` → `not%20a%20url`），
    // 这种输入必须挡在前面，否则会带着一个"看起来合法"的地址去发请求。
    if (RegExp(r'\s').hasMatch(input)) {
      throw const ServerAddressFormatException(
        ServerAddressError.containsWhitespace,
        'contains_whitespace',
      );
    }

    final withScheme = input.contains('://') ? input : 'https://$input';
    final Uri parsed;
    try {
      parsed = Uri.parse(withScheme);
    } on FormatException {
      throw const ServerAddressFormatException(
        ServerAddressError.invalidSyntax,
        'invalid_syntax',
      );
    }

    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw const ServerAddressFormatException(
        ServerAddressError.unsupportedScheme,
        'unsupported_scheme',
      );
    }
    if (parsed.host.isEmpty) {
      throw const ServerAddressFormatException(
        ServerAddressError.missingHost,
        'missing_host',
      );
    }

    // 统一去掉末尾斜杠与多余的查询/片段，保留路径（反代子路径）。
    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return ServerAddress._(
      Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: path,
      ),
    );
  }

  /// 换协议但保留 host/port/path。
  ///
  /// 用途：用户把 `https://host:4433` 写成了 `http://host:4433`，反代会直接
  /// 400（"明文请求打到了 HTTPS 端口"）。这时不该让用户自己去改输入框——
  /// 换一次协议重试就能连上。
  ServerAddress withScheme(String scheme) {
    if (scheme != 'http' && scheme != 'https') {
      throw FormatException('Unsupported scheme: $scheme');
    }
    return ServerAddress._(uri.replace(scheme: scheme));
  }

  /// 用于"这个地址能不能明文"的提示。
  ///
  /// 判断的是"会不会把凭据明文发到公网"，而不是"是不是 HTTPS"：
  /// 家用 NAS 走 `http://192.168.x.x` 是常态，对这种情况告警只会让用户忽略告警；
  /// 公网地址（含域名）走明文才是真的危险。
  bool get isInsecureRemote => !isHttps && !isLoopback && !isPrivateHost;

  /// 内网/链路本地地址：IPv4 的 10/8、172.16/12、192.168/16、169.254/16，
  /// IPv6 的 fc00::/7（ULA）与 fe80::/10（链路本地）。
  bool get isPrivateHost {
    final host = uri.host;
    if (host.isEmpty) return false;

    // mDNS / 家用命名：nas.local、komga.lan、nas.home.arpa 都是局域网内的名字。
    final lower = host.toLowerCase();
    for (final suffix in <String>['.local', '.lan', '.home.arpa']) {
      if (lower.endsWith(suffix)) return true;
    }

    if (host.contains(':')) {
      if (lower.startsWith('fe8') ||
          lower.startsWith('fe9') ||
          lower.startsWith('fea') ||
          lower.startsWith('feb')) {
        return true;
      }
      // fc00::/7 → fc 与 fd 开头
      return lower.startsWith('fc') || lower.startsWith('fd');
    }

    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final first = octets[0];
    final second = octets[1];
    if (first == 10) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    if (first == 169 && second == 254) return true;
    return false;
  }

  @override
  bool operator ==(Object other) => other is ServerAddress && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => baseUrl;
}
