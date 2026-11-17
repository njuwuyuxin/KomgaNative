/// 进度同步的纯逻辑：待提交队列（outbox）+ 多设备对账。
///
/// 这里刻意没有任何 IO：真正的落库与 HTTP 在 app 层，本包只做决策，
/// 因此可以在毫秒级单测里覆盖"离线、并发、跨设备覆盖"等难复现场景。
library;

export 'src/outbox.dart';
export 'src/reconciler.dart';
