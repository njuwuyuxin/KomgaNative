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
    // 自动探测 + 手动强制；探测是异步的，首帧可能还是彩色主题，
    // 但绝不能为了等探测卡住启动。
    final detectedEink = ref.watch(einkDetectedProvider).value ?? false;
    final useEink = settings.forceEink || detectedEink;
    // 触感反馈的总开关只在这里同步一次，页面统一走 AppHaptics。
    AppHaptics.enabled = settings.haptics;

    return ProgressSyncScope(
      child: MaterialApp.router(
        title: 'KomgaNative',
        debugShowCheckedModeBanner: false,
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
