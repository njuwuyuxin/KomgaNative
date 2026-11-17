/// Komga 服务器地址（值对象）。
///
/// 解析用户输入并做规范化：补协议、去尾斜杠、保留子路径（`https://host/komga` 这种反代部署）。
/// 校验放在领域层而不是 UI 层，这样 router / 连接页 / 设置页共用同一套规则。
class ServerAddress {
  const ServerAddress._(this.uri);

  final Uri uri;

  /// 不含结尾斜杠的基址，交给 `KomgaUrls`。
  String get baseUrl => uri.toString();

  String get host => uri.host;
  int? get port => uri.hasPort ? uri.port : null;
  bool get isHttps => uri.scheme == 'https';
  bool get isLoopback =>
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

  /// 宽松解析：用户只输入 `192.168.1.10:25600` 也接受（默认补 https）。
  ///
  /// 抛 [FormatException]，消息可以直接展示给用户。
  static ServerAddress parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('Please enter your Komga server address');
    }
    // `Uri.parse` 会把空格百分号编码进 host（`not a url` → `not%20a%20url`），
    // 这种输入必须挡在前面，否则会带着一个"看起来合法"的地址去发请求。
    if (RegExp(r'\s').hasMatch(input)) {
      throw const FormatException('The address must not contain spaces');
    }

    final withScheme = input.contains('://') ? input : 'https://$input';
    final Uri parsed;
    try {
      parsed = Uri.parse(withScheme);
    } on FormatException {
      throw const FormatException('That does not look like a valid address');
    }

    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw const FormatException('Only http:// and https:// are supported');
    }
    if (parsed.host.isEmpty) {
      throw const FormatException('The address is missing a host name');
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
