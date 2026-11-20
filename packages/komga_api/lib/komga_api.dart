/// Komga REST 访问层。
///
/// - [KomgaSession]：鉴权会话（Basic / API Key）+ 连接流程所需接口；
/// - [KomgaUrls]：URL 构造（页图、缩略图、进度等）；
/// - 错误统一折叠成 [KomgaError]。
library;

export 'src/errors.dart';
export 'src/http_cache.dart';
export 'src/parsers.dart';
export 'src/session.dart';
export 'src/tls.dart';
export 'src/urls.dart';
