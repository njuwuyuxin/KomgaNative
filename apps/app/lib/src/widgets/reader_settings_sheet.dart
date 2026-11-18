import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/widgets/reader_mode_text.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板：模式 / 亮度 / 常亮 / 跳页。
///
/// 为什么放在底部面板而不是顶栏一排图标：四项设置里有两项是"连续值"（亮度、页码），
/// 只有面板放得下；而且它盖住内容的同时还能看到页面在变，调亮度时有参照。
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required int page,
  required int total,
  required ValueChanged<int> onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 内容可能超过默认的 9/16 高度（大字号/平板上的模式说明），必须可滚动。
    isScrollControlled: true,
    backgroundColor: palette.background,
    elevation: palette.isLight ? 0 : 8,
    builder: (BuildContext context) => ReaderSettingsSheet(
      palette: palette,
      page: page,
      total: total,
      onJump: onJump,
    ),
  );
}

class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({
    required this.palette,
    required this.page,
    required this.total,
    required this.onJump,
    super.key,
  });

  final ReaderPalette palette;
  final int page;
  final int total;
  final ValueChanged<int> onJump;

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  /// 拖动中的页码（松手才跳，避免拖动时每帧都改阅读位置）。
  double? _dragging;

  /// 松手后停住的页码。
  ///
  /// 不能在松手时直接丢掉局部状态：`widget.page` 是**打开面板那一刻**的快照，
  /// `onJump` 只会改阅读器、不会重建这个面板。回到 `widget.page` 会让滑条
  /// "弹回原位"，看起来像拖动失败（其实页面已经跳过去了）。
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.page.clamp(1, widget.total < 1 ? 1 : widget.total);
  }

  void _onSlideEnd(double value) {
    final target = value.round().clamp(1, widget.total);
    // 先落本地页码再通知外部：两者顺序反了会有一帧仍显示旧值。
    setState(() {
      _dragging = null;
      _page = target;
    });
    widget.onJump(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(readerPrefsProvider);
    final controller = ref.read(readerPrefsProvider.notifier);
    final palette = widget.palette;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: AppSizes.grabber.width,
                  height: AppSizes.grabber.height,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.outline,
                    borderRadius: BorderRadius.circular(
                      AppSizes.grabber.height / 2,
                    ),
                  ),
                ),
              ),
              Text(
                l10n.readingSettings,
                style: textStyle.titleMedium?.copyWith(
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _Label(l10n.readingMode, palette: palette),
              for (final choice in ReaderModeChoice.values)
                _ModeRow(
                  choice: choice,
                  selected: prefs.mode == choice,
                  palette: palette,
                  onTap: () => controller.setMode(choice),
                ),
              const SizedBox(height: AppSpacing.md),
              _Label(l10n.brightness, palette: palette),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.brightness_low,
                    color: palette.muted,
                    size: AppSizes.iconMd,
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('reader-brightness-slider'),
                      value: prefs.brightness,
                      min: ReaderPrefs.minBrightness,
                      max: 1,
                      activeColor: palette.foreground,
                      inactiveColor: palette.outline,
                      onChanged: controller.setBrightness,
                    ),
                  ),
                  SizedBox(
                    width: AppSizes.valueColumn,
                    child: Text(
                      l10n.brightnessPercent((prefs.brightness * 100).round()),
                      textAlign: TextAlign.end,
                      style: textStyle.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.keepAwake,
                onChanged: controller.setKeepAwake,
                activeThumbColor: palette.foreground,
                title: Text(
                  l10n.keepScreenAwake,
                  style: textStyle.bodyMedium?.copyWith(
                    color: palette.foreground,
                  ),
                ),
                subtitle: Text(
                  l10n.keepScreenAwakeHint,
                  style: textStyle.bodySmall?.copyWith(color: palette.muted),
                ),
              ),
              if (widget.total > 1) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    _Label(l10n.goToPage, palette: palette),
                    const Spacer(),
                    Text(
                      l10n.readerPageOf(
                        _dragging?.round() ?? _page,
                        widget.total,
                      ),
                      style: textStyle.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const Key('reader-jump-slider'),
                  value: (_dragging ?? _page.toDouble()).clamp(
                    1,
                    widget.total.toDouble(),
                  ),
                  min: 1,
                  max: widget.total.toDouble(),
                  divisions: widget.total > 1 ? widget.total - 1 : null,
                  activeColor: palette.foreground,
                  inactiveColor: palette.outline,
                  onChanged: (double value) =>
                      setState(() => _dragging = value),
                  onChangeEnd: _onSlideEnd,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.palette});

  final String text;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: palette.muted,
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.choice,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ReaderModeChoice choice;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return InkWell(
      key: Key('reader-mode-${choice.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: AppSizes.iconMd,
              color: selected ? palette.foreground : palette.muted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    readerModeLabel(l10n, choice),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.foreground,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  // 说明只给选中项看：四个选项全带说明会把面板撑到屏幕外，
                  // 而用户真正需要解释的只有"我正要选的那个"。
                  if (selected)
                    Text(
                      readerModeHint(l10n, choice),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
