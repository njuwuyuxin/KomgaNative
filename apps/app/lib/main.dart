import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 液态玻璃着色器：只在 Impeller 上加载；失败自动用合成版玻璃。
  await LiquidGlassProgram.ensureLoaded();
  runApp(const ProviderScope(child: KomgaApp()));
}
