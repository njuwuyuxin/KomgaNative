import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 冷启动读取钥匙串期间的过渡页。
///
/// 只做一件事：不要让用户看到空白，也不要闪现"未登录"再跳走。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('KomgaNative', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(
              width: AppSizes.iconMd,
              height: AppSizes.iconMd,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
