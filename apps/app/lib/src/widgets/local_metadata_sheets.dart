import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 打开本地系列元数据编辑底部面板（LMA-10）。
Future<bool> showEditLocalSeriesSheet(
  BuildContext context,
  WidgetRef ref,
  Series series,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => _EditSeriesSheet(series: series),
  );
  return saved ?? false;
}

/// 打开本地单本书籍标题与卷号编辑弹窗（LMA-10）。
Future<bool> showEditLocalBookDialog(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController(text: book.name);
  final numCtrl = TextEditingController(text: book.number);
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('edit-local-book-dialog'),
        title: Text(l10n.editMetadata),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('edit-book-title-field'),
              controller: nameCtrl,
              decoration: InputDecoration(labelText: l10n.editBookTitleLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('edit-book-number-field'),
              controller: numCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l10n.editBookNumberLabel),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('edit-book-save'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || nameCtrl.text.trim().isEmpty) return false;
    await ref
        .read(localCatalogMutatorProvider)
        .editBook(
          book.id,
          seriesId: book.seriesId,
          name: nameCtrl.text,
          number: numCtrl.text,
        );
    return true;
  } finally {
    nameCtrl.dispose();
    numCtrl.dispose();
  }
}

/// 打开将多个本地系列合并为一个系列的确认弹窗（LMA-10）。
Future<bool> showMergeLocalSeriesDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<String> selectedIds,
  required String defaultTitle,
}) async {
  if (selectedIds.length < 2) return false;
  final l10n = AppLocalizations.of(context);
  final titleCtrl = TextEditingController(text: defaultTitle);
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('merge-local-series-dialog'),
        title: Text(l10n.mergeSeriesDialogTitle),
        content: TextField(
          key: const Key('merge-series-title-field'),
          controller: titleCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.mergeTargetSeriesHint),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('merge-series-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || titleCtrl.text.trim().isEmpty) return false;
    await ref
        .read(localCatalogMutatorProvider)
        .mergeSeries(
          sourceSeriesIds: selectedIds,
          targetSeriesId: selectedIds.first,
          mergedTitle: titleCtrl.text,
        );
    return true;
  } finally {
    titleCtrl.dispose();
  }
}

class _EditSeriesSheet extends ConsumerStatefulWidget {
  const _EditSeriesSheet({required this.series});

  final Series series;

  @override
  ConsumerState<_EditSeriesSheet> createState() => _EditSeriesSheetState();
}

class _EditSeriesSheetState extends ConsumerState<_EditSeriesSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.series.title,
  );
  late final TextEditingController _authors = TextEditingController(
    text: widget.series.authors.join(', '),
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.series.tags.join(', '),
  );
  late final TextEditingController _summary = TextEditingController(
    text: widget.series.summary ?? '',
  );
  late ReadingDirection _direction = widget.series.readingDirection;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _authors.dispose();
    _tags.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await ref
        .read(localCatalogMutatorProvider)
        .editSeries(
          widget.series.id,
          title: _title.text,
          summary: _summary.text,
          authors: _splitCsv(_authors.text),
          tags: _splitCsv(_tags.text),
          readingDirection: _direction,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  static List<String> _splitCsv(String raw) => <String>[
    for (final part in raw.split(RegExp('[,，]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    const directions = <ReadingDirection>[
      ReadingDirection.unknown,
      ReadingDirection.leftToRight,
      ReadingDirection.rightToLeft,
      ReadingDirection.vertical,
    ];

    return Padding(
      key: const Key('edit-local-series-sheet'),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        bottomInset + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.editMetadata,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('edit-series-title-field'),
              controller: _title,
              decoration: InputDecoration(labelText: l10n.editSeriesTitleLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('edit-series-authors-field'),
              controller: _authors,
              decoration: InputDecoration(labelText: l10n.editAuthorsLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('edit-series-tags-field'),
              controller: _tags,
              decoration: InputDecoration(labelText: l10n.editTagsLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('edit-series-summary-field'),
              controller: _summary,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.editSummaryLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final dir in directions)
                  ChoiceChip(
                    key: Key('edit-series-dir-${dir.name}'),
                    label: Text(_dirLabel(l10n, dir)),
                    selected: _direction == dir,
                    onSelected: (bool ok) {
                      if (ok) setState(() => _direction = dir);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            GlassPillButton(
              key: const Key('edit-series-save'),
              expanded: true,
              busy: _saving,
              icon: Icons.check,
              label: MaterialLocalizations.of(context).okButtonLabel,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  static String _dirLabel(AppLocalizations l10n, ReadingDirection d) =>
      switch (d) {
        ReadingDirection.leftToRight => l10n.readerDirectionLtr,
        ReadingDirection.rightToLeft => l10n.readerDirectionRtl,
        ReadingDirection.vertical ||
        ReadingDirection.webtoon => l10n.readerModeVertical,
        ReadingDirection.unknown => l10n.readerModeAuto,
      };
}
