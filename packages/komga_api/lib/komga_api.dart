/// Komga REST 访问层。
///
/// M0 只包含：错误模型、URL 构造、传输层骨架。
/// DTO 将由 `tool/codegen` 从 OpenAPI 快照生成到 `lib/generated/`（M1）。
library;

export 'src/errors.dart';
export 'src/transport.dart';
export 'src/urls.dart';
