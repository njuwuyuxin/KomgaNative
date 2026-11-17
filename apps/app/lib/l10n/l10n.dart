import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';

/// 应用实际使用的本地化 delegate 列表。
///
/// 为什么不用生成代码里的 `AppLocalizations.localizationsDelegates`：
/// 那份列表固定引用 `flutter_localizations` 的 GlobalMaterialLocalizations，
/// 而本项目的 Material 控件来自 `material_ui` 包——两者不是同一个
/// `MaterialLocalizations` 类型。直接用它时中文会报
/// "A MaterialLocalizations delegate that supports the zh locale was not found"，
/// 页面直接抛异常。`material_ui` 自带的 delegate 同时包含 Material / Cupertino /
/// Widgets，正好是 `MaterialApp` 需要的那一套。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];
