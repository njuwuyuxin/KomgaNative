import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/providers/router_provider.dart';
import 'package:komga_native/src/widgets/progress_sync_scope.dart';

/// 应用根。
///
/// 主题选择逻辑：墨水屏一律用 eink 主题（并且忽略深色模式），
/// 这样"墨水屏档位"只在一处生效，页面不需要各自判断。
///
/// 语言只在这里接一次：`locale` 为 null 时由 Flutter 按系统语言在
/// `supportedLocales` 里挑（默认跟随系统），选过语言就是固定 locale。
class KomgaApp extends ConsumerWidget {
  const KomgaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final einkTheme = AppTheme.eink();
    // 自动探测 + 手动强制统一由 `effectiveEinkProvider` 决定，阅读器等页面读同一个值。
    final useEink = ref.watch(effectiveEinkProvider);
    // 触感反馈的总开关由状态变更监听驱动，避免在 build 主体写静态全局变量。
    ref.listen<bool>(
      settingsProvider.select((SettingsState s) => s.haptics),
      (_, bool enabled) => AppHaptics.enabled = enabled,
    );

    return ProgressSyncScope(
      child: MaterialApp.router(
        title: 'Yomu',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _NoOverscrollBehavior(),
        locale: settings.language.locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: useEink ? einkTheme : AppTheme.light(),
        darkTheme: useEink ? einkTheme : AppTheme.dark(),
        themeMode: useEink ? ThemeMode.light : settings.themeMode,
        routerConfig: router,
      ),
    );
  }
}

/// 全局关掉 Android 拉伸/辉光过度滚动效果。
///
/// Android 12+ 的 `StretchingOverscrollIndicator` 会给整条滚动层施加拉伸矩阵，
/// 而液态玻璃着色器按屏幕坐标采样背景（`liquid_glass.frag`），下拉/拖动时会读到
/// 变换后的空图层或错位纹理，导致正在读卡片、搜索栏、设置分段控件变黑/变灰、
/// 书详情按钮边缘溢彩。`RefreshIndicator` 仅依赖 `OverscrollNotification`，
/// iOS 仍保持默认弹性滚动，二者都不受影响。
class _NoOverscrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
