import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu_reader/yomu_reader.dart';

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

/// 宽页自动切分的界面文案（LMB-01）。
String readerSplitWideLabel(AppLocalizations l10n, WidePageSplitMode mode) =>
    switch (mode) {
      WidePageSplitMode.off => l10n.readerSplitWideOff,
      WidePageSplitMode.autoPortrait => l10n.readerSplitWideAuto,
      WidePageSplitMode.always => l10n.readerSplitWideAlways,
    };

String readerSplitWideHint(AppLocalizations l10n, WidePageSplitMode mode) =>
    switch (mode) {
      WidePageSplitMode.off => l10n.readerSplitWideOffHint,
      WidePageSplitMode.autoPortrait => l10n.readerSplitWideAutoHint,
      WidePageSplitMode.always => l10n.readerSplitWideAlwaysHint,
    };
