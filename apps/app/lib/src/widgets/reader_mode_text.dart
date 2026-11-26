import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';

/// 阅读模式的界面文案（数据层只保留枚举，文案全在 ARB）。
String readerModeLabel(AppLocalizations l10n, ReaderModeChoice choice) =>
    switch (choice) {
      ReaderModeChoice.auto => l10n.readerModeAuto,
      ReaderModeChoice.single => l10n.readerModeSingle,
      ReaderModeChoice.double => l10n.readerModeDouble,
      ReaderModeChoice.vertical => l10n.readerModeVertical,
    };

String readerModeHint(AppLocalizations l10n, ReaderModeChoice choice) =>
    switch (choice) {
      ReaderModeChoice.auto => l10n.readerModeAutoHint,
      ReaderModeChoice.single => l10n.readerModeSingleHint,
      ReaderModeChoice.double => l10n.readerModeDoubleHint,
      ReaderModeChoice.vertical => l10n.readerModeVerticalHint,
    };
