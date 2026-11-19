import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart'
    show TapZonePreset;
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页的"阅读"分组（SET-01）：把阅读器面板里的默认值提升到设置里。
///
/// 只提升**最常改的两项**（阅读模式、翻页动画）：全搬过来会变成第二个阅读设置面板，
/// 而且"无重复设置"这条要求也站不住。其余（适配/方向/背景/亮度）仍在阅读器里调，
/// 一次只对一本书生效，本来就该在书里改。
class SettingsReadingSection extends ConsumerWidget {
  const SettingsReadingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(readerPrefsProvider);
    final controller = ref.read(readerPrefsProvider.notifier);

    return AppListGroup(
      header: l10n.settingsReading,
      children: <Widget>[
        ListTile(
          key: const Key('settings-reading-mode'),
          title: Text(l10n.readingMode),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final mode in ReaderModeChoice.values)
                  ChoiceChip(
                    key: Key('settings-reading-mode-${mode.name}'),
                    label: Text(_modeLabel(l10n, mode)),
                    selected: prefs.mode == mode,
                    onSelected: (bool selected) {
                      if (selected) controller.setMode(mode);
                    },
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          key: const Key('settings-page-turn'),
          title: Text(l10n.readerPageTurn),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final choice in ReaderPageTurnChoice.values)
                  ChoiceChip(
                    key: Key('settings-page-turn-${choice.name}'),
                    label: Text(_turnLabel(l10n, choice)),
                    selected: prefs.pageTurn == choice,
                    onSelected: (bool selected) {
                      if (selected) controller.setPageTurn(choice);
                    },
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          key: const Key('settings-tablet-layout'),
          title: Text(l10n.settingsTabletLayout),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final choice in TabletLayoutChoice.values)
                      ChoiceChip(
                        key: Key('settings-tablet-layout-${choice.name}'),
                        label: Text(_tabletLabel(l10n, choice)),
                        selected: prefs.tabletLayout == choice,
                        onSelected: (bool selected) {
                          if (selected) controller.setTabletLayout(choice);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.settingsTabletLayoutHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        ListTile(
          key: const Key('settings-tap-zones'),
          title: Text(l10n.settingsTapZones),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final preset in TapZonePreset.values)
                      ChoiceChip(
                        key: Key('settings-tap-zone-${preset.name}'),
                        label: Text(_tapZoneLabel(l10n, preset)),
                        selected: prefs.tapZone == preset,
                        onSelected: (bool selected) {
                          if (selected) controller.setTapZone(preset);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.settingsTapZonesHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        ListTile(
          key: const Key('settings-auto-scroll-speed'),
          title: Text(l10n.settingsAutoScrollSpeed),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Slider(
                value: prefs.autoScrollSpeed.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '${prefs.autoScrollSpeed}',
                onChanged: (double value) =>
                    controller.setAutoScrollSpeed(value.round()),
              ),
              Text(
                l10n.settingsAutoScrollSpeedHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('settings-invert-tap-zones'),
          value: prefs.invertTapZones,
          title: Text(l10n.settingsInvertTapZones),
          onChanged: controller.setInvertTapZones,
        ),
        SwitchListTile(
          key: const Key('settings-double-tap-zoom'),
          value: prefs.doubleTapZoom,
          title: Text(l10n.settingsDoubleTapZoom),
          onChanged: controller.setDoubleTapZoom,
        ),
        SwitchListTile(
          key: const Key('settings-show-session-time'),
          value: prefs.showSessionTime,
          title: Text(l10n.settingsShowSessionTime),
          subtitle: Text(l10n.settingsShowSessionTimeHint),
          onChanged: controller.setShowSessionTime,
        ),
      ],
    );
  }

  static String _tapZoneLabel(AppLocalizations l10n, TapZonePreset preset) =>
      switch (preset) {
        TapZonePreset.automatic => l10n.tapZoneAutomatic,
        TapZonePreset.leftRight => l10n.tapZoneLeftRight,
        TapZonePreset.lShaped => l10n.tapZoneLShaped,
        TapZonePreset.kindle => l10n.tapZoneKindle,
        TapZonePreset.edge => l10n.tapZoneEdge,
      };

  static String _tabletLabel(
    AppLocalizations l10n,
    TabletLayoutChoice choice,
  ) => switch (choice) {
    TabletLayoutChoice.auto => l10n.tabletLayoutAuto,
    TabletLayoutChoice.single => l10n.tabletLayoutSingle,
    TabletLayoutChoice.double => l10n.tabletLayoutDouble,
  };

  static String _modeLabel(AppLocalizations l10n, ReaderModeChoice mode) =>
      switch (mode) {
        ReaderModeChoice.auto => l10n.readerModeAuto,
        ReaderModeChoice.single => l10n.readerModeSingle,
        ReaderModeChoice.double => l10n.readerModeDouble,
        ReaderModeChoice.vertical => l10n.readerModeVertical,
      };

  static String _turnLabel(
    AppLocalizations l10n,
    ReaderPageTurnChoice choice,
  ) => switch (choice) {
    ReaderPageTurnChoice.curl => l10n.readerPageTurnCurl,
    ReaderPageTurnChoice.slide => l10n.readerPageTurnSlide,
    ReaderPageTurnChoice.fade => l10n.readerPageTurnFade,
    ReaderPageTurnChoice.none => l10n.readerPageTurnNone,
  };
}

/// 设置页的"书架"分组（SET-01）：默认呈现方式与封面档位。
///
/// 写的是 `ShelfController` 的 setter，和书架顶部那三颗按钮**同一份状态**——
/// 从设置改和从书架改完全等价，不会出现"设置了却没生效"。
class SettingsLibrarySection extends ConsumerWidget {
  const SettingsLibrarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 没有连接服务器时 `shelfProvider` 会直接抛（"未连接服务器时不应读取书架"），
    // 这一组也就没有意义——整组不显示，而不是让设置页跟着炸。
    if (ref.watch(sessionProvider) is! SessionConnected) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);

    return AppListGroup(
      header: l10n.settingsLibrary,
      children: <Widget>[
        ListTile(
          key: const Key('settings-library-view'),
          title: Text(l10n.shelfViewTooltip),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final view in ShelfView.values)
                  ChoiceChip(
                    key: Key('settings-library-view-${view.name}'),
                    label: Text(
                      view == ShelfView.grid ? l10n.viewGrid : l10n.viewList,
                    ),
                    selected: state.view == view,
                    onSelected: (bool selected) {
                      if (selected) controller.setView(view);
                    },
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          key: const Key('settings-library-cover'),
          title: Text(l10n.coverSize),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final size in ShelfCoverSize.values)
                  ChoiceChip(
                    key: Key('settings-library-cover-${size.name}'),
                    label: Text(_coverLabel(l10n, size)),
                    selected: state.coverSize == size,
                    onSelected: (bool selected) {
                      if (selected) controller.setCoverSize(size);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _coverLabel(AppLocalizations l10n, ShelfCoverSize size) =>
      switch (size) {
        ShelfCoverSize.small => l10n.coverSmall,
        ShelfCoverSize.medium => l10n.coverMedium,
        ShelfCoverSize.large => l10n.coverLarge,
      };
}

/// 让 `AppSettings` 在本文件里被引用（分段控件的持久化走 setter，不直接写它）。
// ignore: unused_element
typedef _SettingsSnapshot = AppSettings;
