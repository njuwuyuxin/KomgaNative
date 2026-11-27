import 'package:material_ui/material_ui.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 底部勾选抽屉通用外框（供收藏集、阅读列表、系列选择器三处复用，P2-7）。
class PickerSheetShell extends StatelessWidget {
  const PickerSheetShell({
    super.key,
    required this.sheetKey,
    required this.maxHeightFactor,
    required this.title,
    required this.body,
    required this.footer,
    this.headerAction,
    this.showSearch = false,
    this.searchKey,
    this.searchHint,
    this.onSearchChanged,
  });

  final Key sheetKey;
  final double maxHeightFactor;
  final String title;
  final Widget? headerAction;
  final bool showSearch;
  final Key? searchKey;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return ConstrainedBox(
      key: sheetKey,
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                headerAction == null ? AppSpacing.md : AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  ?headerAction,
                ],
              ),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: TextField(
                  key: searchKey,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            Flexible(child: body),
            const Divider(height: AppSizes.hairline),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(width: double.infinity, child: footer),
            ),
          ],
        ),
      ),
    );
  }
}
