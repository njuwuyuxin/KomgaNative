import 'package:drift/drift.dart';

/// 本地进度 + 待提交队列（合一张表：按 `{scope, bookId}` 分区，pending 非空即可提交）。
class LocalProgress extends Table {
  /// 服务器分区键（规范化 `baseUrl`）；空串兼容未分区单测与旧存档。
  TextColumn get scope => text().withDefault(const Constant(''))();

  TextColumn get bookId => text()();

  IntColumn get page => integer()();

  BoolColumn get completed => boolean()();

  /// 本地写入时间：只用于展示/诊断，**不参与对账**（设备墙钟不可信）。
  DateTimeColumn get updatedAt => dateTime()();

  /// 上次确认过的服务端 `lastModified`；PATCH 成功后置空（见 ADR 0002 决策 4）。
  DateTimeColumn get serverLastModified => dateTime().nullable()();

  /// 非空 = 有未提交更新；提交回执 seq 与它相等才清空。
  IntColumn get pendingSeq => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope, bookId};
}

/// 置顶的系列（LIB-02 / ARC-06 归位至用户库）。
///
/// 按 **serverId 分区**：切服务器不能串（同一台机器可能连过多个 Komga）。
class PinnedSeriesRows extends Table {
  TextColumn get serverId => text()();

  TextColumn get seriesId => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{serverId, seriesId};
}

/// 一次阅读会话（HIS-01 / ARC-06 归位至用户库 / ARC-07 补齐服务器分区）。
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属服务器标识（规范化 `baseUrl`）；默认空串兼容旧历史行。
  TextColumn get scope => text().withDefault(const Constant(''))();

  TextColumn get bookId => text()();

  TextColumn get seriesId => text()();

  TextColumn get bookName => text().withDefault(const Constant(''))();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get endedAt => dateTime()();

  IntColumn get durationMs => integer()();

  IntColumn get startPage => integer().withDefault(const Constant(1))();

  IntColumn get endPage => integer().withDefault(const Constant(1))();

  /// 这本书在本次会话结束时是否已读完（用于"读完的书"统计）。
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}
