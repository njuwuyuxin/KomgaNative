import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_settings_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 一组设置的小标题 + 该组的"重置"（RDR-04）。
///
/// 每组独立重置：用户把"颜色"调坏了，不该顺手把"布局"也打回默认。
/// 已经是默认值时按钮置灰——点一个什么都不会发生的按钮比没有按钮更糟。
class ReaderSettingsGroupHeader extends StatelessWidget {
  const ReaderSettingsGroupHeader({
    required this.group,
    required this.title,
    required this.palette,
    required this.enabled,
    required this.onReset,
    super.key,
  });

  /// 组名用来生成 `reader-reset-<group>` 这个 key。
  final String group;
  final String title;
  final ReaderPalette palette;
  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: ReaderSectionLabel(title, palette: palette)),
          TextButton(
            key: Key('reader-reset-$group'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
              foregroundColor: palette.foreground,
              disabledForegroundColor: palette.outline,
            ),
            onPressed: enabled ? onReset : null,
            child: Text(l10n.readerResetGroup),
          ),
        ],
      ),
    );
  }
}

/// 面板里的一个开关（标题 + 说明）。
class ReaderSettingsSwitch extends StatelessWidget {
  const ReaderSettingsSwitch({
    required this.switchKey,
    required this.value,
    required this.title,
    required this.hint,
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final Key switchKey;
  final bool value;
  final String title;
  final String hint;
  final ReaderPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      key: switchKey,
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: palette.foreground,
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(color: palette.foreground),
      ),
      subtitle: Text(
        hint,
        style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
      ),
    );
  }
}

/// "跳转到页"滑条。
///
/// 拖动过程中只改本地值，松手才跳：否则每拖动一帧都会写一次进度、
/// 触发一次页图请求。
class ReaderJumpSlider extends StatefulWidget {
  const ReaderJumpSlider({
    required this.page,
    required this.total,
    required this.palette,
    required this.onJump,
    super.key,
  });

  /// 打开面板时的页码；之后由本地状态接管。
  final int page;
  final int total;
  final ReaderPalette palette;
  final ValueChanged<int> onJump;

  @override
  State<ReaderJumpSlider> createState() => _ReaderJumpSliderState();
}

class _ReaderJumpSliderState extends State<ReaderJumpSlider> {
  double? _dragging;

  /// 松手后停住的页码。
  ///
  /// 不能直接回落到 `widget.page`：它是**打开面板那一刻**的快照，
  /// `onJump` 只改阅读器、不重建面板，回退会让滑条"弹回原位"。
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.page.clamp(1, widget.total < 1 ? 1 : widget.total);
  }

  void _onSlideEnd(double value) {
    final target = value.round().clamp(1, widget.total);
    setState(() {
      _dragging = null;
      _page = target;
    });
    widget.onJump(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.total <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ReaderSectionLabel(l10n.goToPage, palette: widget.palette),
            const Spacer(),
            Text(
              l10n.readerPageOf(_dragging?.round() ?? _page, widget.total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: widget.palette.muted,
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
          activeColor: widget.palette.foreground,
          inactiveColor: widget.palette.outline,
          onChanged: (double value) => setState(() => _dragging = value),
          onChangeEnd: _onSlideEnd,
        ),
      ],
    );
  }
}
