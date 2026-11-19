import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃胶囊搜索框（iOS 的 search field 形态）。
///
/// 与标题栏同一材质：背后内容模糊着穿过、左边放大镜、有内容时右边出现清除键。
/// 输入框本身没有边框和填充色（`InputBorder.none` + `filled: false`）——
/// 填充会盖掉玻璃的底色与高光，看起来又变回一块 Material 输入框。
///
/// 墨水屏：玻璃退化成纸底墨边，输入区仍是白底黑字。
class GlassSearchField extends StatelessWidget {
  const GlassSearchField({
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.clearLabel,
    this.autofocus = false,
    this.focusNode,
    this.textInputAction = TextInputAction.search,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 清除键的读屏 / 长按提示；为空时清除键没有 Tooltip（仍可点）。
  final String? clearLabel;

  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      child: SizedBox(
        height: AppSizes.glassSearchHeight,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          style: theme.textTheme.bodyLarge,
          cursorColor: scheme.primary,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(color: muted),
            hintMaxLines: 1,
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(Icons.search, size: AppSizes.iconMd, color: muted),
            prefixIconConstraints: const BoxConstraints(
              minWidth: AppSizes.glassSearchHeight,
              minHeight: AppSizes.glassSearchHeight,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, TextEditingValue value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                final clear = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                  child: SizedBox(
                    width: AppSizes.glassSearchHeight,
                    height: AppSizes.glassSearchHeight,
                    child: Icon(
                      Icons.cancel,
                      size: AppSizes.iconSm,
                      color: muted,
                    ),
                  ),
                );
                return Semantics(
                  button: true,
                  label: clearLabel,
                  child: clearLabel == null
                      ? clear
                      : Tooltip(message: clearLabel!, child: clear),
                );
              },
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: AppSizes.glassSearchHeight,
              minHeight: AppSizes.glassSearchHeight,
            ),
          ),
        ),
      ),
    );
  }
}
