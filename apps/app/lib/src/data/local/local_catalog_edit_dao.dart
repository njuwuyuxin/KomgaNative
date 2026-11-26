import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// [ProgressDatabase] 的本地元数据编辑、系列合并/拆分与自定义封面扩展（LMA-10 / LMA-11）。
extension LocalCatalogEditDao on ProgressDatabase {
  /// 修改本地系列元数据并置 `metadataLocked = true` 锁定保护。
  Future<void> updateLocalSeriesMetadata(
    String seriesId, {
    required String title,
    String? summary,
    String? publisher,
    List<String>? authors,
    List<String>? tags,
    ReadingDirection? readingDirection,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;
    final now = DateTime.now().toUtc();

    await (update(localSeriesRows)..where((t) => t.id.equals(seriesId))).write(
      LocalSeriesRowsCompanion(
        title: Value<String>(trimmedTitle),
        titleSort: Value<String>(normalizeTitleSort(trimmedTitle)),
        summary: summary != null
            ? Value<String>(summary.trim())
            : const Value.absent(),
        publisher: publisher != null
            ? Value<String>(publisher.trim())
            : const Value.absent(),
        authorsJson: authors != null
            ? Value<String>(jsonEncode(_cleanList(authors)))
            : const Value.absent(),
        tagsJson: tags != null
            ? Value<String>(jsonEncode(_cleanList(tags)))
            : const Value.absent(),
        readingDirection: readingDirection != null
            ? Value<String>(readingDirection.name)
            : const Value.absent(),
        metadataLocked: const Value<bool>(true),
        updatedAt: Value<DateTime>(now),
      ),
    );
  }

  /// 修改本地单本书籍标题与卷号（自动重算 `numberSort` 以更新系列内排序）。
  Future<void> updateLocalBookMetadata(
    String bookId, {
    required String name,
    required String number,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    final trimmedNum = number.trim();
    final sortVal = double.tryParse(trimmedNum) ?? 0;

    await (update(localBooksRows)..where((t) => t.id.equals(bookId))).write(
      LocalBooksRowsCompanion(
        name: Value<String>(trimmedName),
        number: Value<String>(trimmedNum),
        numberSort: Value<double>(sortVal),
      ),
    );
  }

  /// 将多个本地系列合并进 [targetSeriesId]，清理被抽空的源系列并同步修正收藏集引用。
  Future<void> mergeLocalSeriesInto({
    required List<String> sourceSeriesIds,
    required String targetSeriesId,
    String? mergedTitle,
  }) {
    return transaction(() async {
      final target = await (select(
        localSeriesRows,
      )..where((t) => t.id.equals(targetSeriesId))).getSingleOrNull();
      if (target == null) return;

      final others = sourceSeriesIds
          .where((id) => id != targetSeriesId && id.startsWith('local:'))
          .toSet();
      if (others.isEmpty && mergedTitle == null) return;

      for (final sid in others) {
        await (update(
          localBooksRows,
        )..where((t) => t.seriesId.equals(sid))).write(
          LocalBooksRowsCompanion(seriesId: Value<String>(targetSeriesId)),
        );
        await (delete(localSeriesRows)..where((t) => t.id.equals(sid))).go();
        await (delete(pinnedSeriesRows)..where(
              (t) =>
                  t.serverId.equals(kLocalSourceKey) & t.seriesId.equals(sid),
            ))
            .go();
      }

      if (others.isNotEmpty) {
        final collections = await select(localCollectionsRows).get();
        for (final col in collections) {
          final ids = decodeJsonStringList(col.seriesIdsJson);
          var touched = false;
          final seen = <String>{};
          final nextIds = <String>[];
          for (final id in ids) {
            final mapped = others.contains(id) ? targetSeriesId : id;
            if (mapped != id) touched = true;
            if (seen.add(mapped)) nextIds.add(mapped);
          }
          if (touched) {
            await (update(
              localCollectionsRows,
            )..where((t) => t.id.equals(col.id))).write(
              LocalCollectionsRowsCompanion(
                seriesIdsJson: Value<String>(jsonEncode(nextIds)),
                updatedAt: Value<DateTime>(DateTime.now().toUtc()),
              ),
            );
          }
        }
      }

      final cleanTitle = mergedTitle?.trim();
      await (update(
        localSeriesRows,
      )..where((t) => t.id.equals(targetSeriesId))).write(
        LocalSeriesRowsCompanion(
          title: (cleanTitle != null && cleanTitle.isNotEmpty)
              ? Value<String>(cleanTitle)
              : const Value.absent(),
          titleSort: (cleanTitle != null && cleanTitle.isNotEmpty)
              ? Value<String>(normalizeTitleSort(cleanTitle))
              : const Value.absent(),
          metadataLocked: const Value<bool>(true),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        ),
      );
    });
  }

  /// 将某本书从多卷系列中拆出成为独立系列（若原系列只有这一本则无需拆分，返回原系列 id）。
  Future<String?> splitLocalBookToStandaloneSeries(
    String bookId, {
    required String Function() generateSeriesId,
    String? customSeriesTitle,
  }) {
    return transaction(() async {
      final bookRow = await (select(
        localBooksRows,
      )..where((t) => t.id.equals(bookId))).getSingleOrNull();
      if (bookRow == null) return null;

      final siblings = await (select(
        localBooksRows,
      )..where((t) => t.seriesId.equals(bookRow.seriesId))).get();
      if (siblings.length <= 1) return bookRow.seriesId;

      final oldSeries = await (select(
        localSeriesRows,
      )..where((t) => t.id.equals(bookRow.seriesId))).getSingleOrNull();
      final now = DateTime.now().toUtc();
      final newSeriesId = generateSeriesId();
      final title = (customSeriesTitle?.trim().isNotEmpty ?? false)
          ? customSeriesTitle!.trim()
          : bookRow.name;

      await into(localSeriesRows).insert(
        LocalSeriesRowsCompanion.insert(
          id: newSeriesId,
          title: title,
          titleSort: normalizeTitleSort(title),
          readingDirection: Value<String>(
            oldSeries?.readingDirection ?? ReadingDirection.unknown.name,
          ),
          coverBookId: Value<String?>(bookId),
          metadataLocked: const Value<bool>(true),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await (update(localBooksRows)..where((t) => t.id.equals(bookId))).write(
        LocalBooksRowsCompanion(seriesId: Value<String>(newSeriesId)),
      );

      if (oldSeries != null && oldSeries.coverBookId == bookId) {
        final firstRemaining = siblings.firstWhere((b) => b.id != bookId);
        await (update(
          localSeriesRows,
        )..where((t) => t.id.equals(oldSeries.id))).write(
          LocalSeriesRowsCompanion(
            coverBookId: Value<String?>(firstRemaining.id),
            updatedAt: Value<DateTime>(now),
          ),
        );
      }

      return newSeriesId;
    });
  }

  /// 更新本地书籍及其所属系列的自定义封面相对路径（LMA-11）。
  Future<void> setLocalCoverPaths({
    required String bookId,
    required String seriesId,
    required String coverRelativePath,
  }) {
    return transaction(() async {
      await (update(localBooksRows)..where((t) => t.id.equals(bookId))).write(
        LocalBooksRowsCompanion(
          coverThumbPath: Value<String?>(coverRelativePath),
        ),
      );
      await (update(
        localSeriesRows,
      )..where((t) => t.id.equals(seriesId))).write(
        LocalSeriesRowsCompanion(
          customCoverPath: Value<String?>(coverRelativePath),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        ),
      );
    });
  }
}

List<String> _cleanList(List<String> items) {
  final seen = <String>{};
  return <String>[
    for (final raw in items)
      if (raw.trim().isNotEmpty && seen.add(raw.trim())) raw.trim(),
  ];
}
