import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_settings_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板顶部的"预设"区（UI-P3-1）。
///
/// 交互只有三件事：保存当前设置、点一下应用、点 × 删除。重命名不做——
/// 面板里再塞一个输入流程会把它撑得更长；名字保存时就能起对。
class ReaderPresetSection extends StatelessWidget {
  const ReaderPresetSection({
    required this.presets,
    required this.palette,
    required this.onApply,
    required this.onDelete,
    required this.onSave,
    super.key,
  });

  final List<ReaderPreset> presets;
  final ReaderPalette palette;
  final ValueChanged<String> onApply;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ReaderSectionLabel(l10n.readerPresets, palette: palette),
            ),
            TextButton.icon(
              key: const Key('reader-preset-save'),
              onPressed: () => _promptName(context, l10n),
              icon: const Icon(Icons.add, size: AppSizes.iconSm),
              label: Text(l10n.readerPresetSave),
              style: TextButton.styleFrom(foregroundColor: palette.foreground),
            ),
          ],
        ),
        if (presets.isEmpty)
          Text(l10n.readerPresetEmpty, style: muted)
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final preset in presets)
                ReaderPresetChip(
                  key: Key('reader-preset-${preset.id}'),
                  preset: preset,
                  palette: palette,
                  onApply: () => onApply(preset.id),
                  onDelete: () => onDelete(preset.id),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _promptName(BuildContext context, AppLocalizations l10n) async {
    var name = l10n.readerPresetDefaultName(presets.length + 1);
    final saved = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.readerPresetName),
        content: TextFormField(
          key: const Key('reader-preset-name'),
          initialValue: name,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (String value) => name = value,
          onFieldSubmitted: (String value) => Navigator.of(context).pop(value),
          decoration: InputDecoration(hintText: l10n.readerPresetName),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('reader-preset-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('reader-preset-confirm'),
            onPressed: () => Navigator.of(context).pop(name),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved == null || saved.trim().isEmpty) return;
    onSave(saved);
  }
}

/// 一个预设 chip。
///
/// 不用 `InputChip`：它的默认底色来自 Material 主题，在深色阅读面板上会变成
/// 一块白底，而标签又是白色（设备上实测"只剩一个白块"）。这里直接用
/// chrome 材质做底 + 白字，阅读器的深浅色与系统主题无关。
class ReaderPresetChip extends StatelessWidget {
  const ReaderPresetChip({
    required this.preset,
    required this.palette,
    required this.onApply,
    required this.onDelete,
    super.key,
  });

  final ReaderPreset preset;
  final ReaderPalette palette;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: palette.foreground);
    return Semantics(
      button: true,
      label: preset.name,
      onTap: onApply,
      child: Material(
        color: palette.chromeMaterial.tint,
        shape: StadiumBorder(side: BorderSide(color: palette.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onApply,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.xxs,
              top: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: l10n.readerPresetDelete,
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.close,
                    size: AppSizes.iconSm,
                    color: palette.muted,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: AppSizes.minTouch,
                    height: AppSizes.minTouch,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
