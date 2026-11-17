import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';

/// 自适应外壳：手机用底部导航，平板/桌面用侧边导航。
///
/// 断点判断只在这里做一次，页面内部不再自己判断"是不是平板"。
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const List<({IconData icon, IconData selectedIcon, String label})>
  _destinations = <({IconData icon, IconData selectedIcon, String label})>[
    (
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
      label: 'Library',
    ),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  void _onSelect(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final sizeClass = WindowSizeClass.of(MediaQuery.sizeOf(context).width);

    if (!sizeClass.useNavigationRail) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _onSelect,
          destinations: <Widget>[
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _onSelect,
            labelType: NavigationRailLabelType.all,
            destinations: <NavigationRailDestination>[
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
