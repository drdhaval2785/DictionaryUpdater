import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_center_screen.dart';
import 'settings_screen.dart';
import 'user_manual_screen.dart';
import 'about_us_screen.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const SyncCenterScreen(),
    const SettingsScreen(),
    const UserManualScreen(),
    const AboutUsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.sync),
                  selectedIcon: Icon(Icons.sync_alt),
                  label: Text('Sources'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  selectedIcon: Icon(Icons.settings_applications),
                  label: Text('Settings'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.book),
                  selectedIcon: Icon(Icons.book_online),
                  label: Text('Manual'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.info),
                  selectedIcon: Icon(Icons.info_outline),
                  label: Text('About Us'),
                ),
              ],
            ),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.sync),
                  label: 'Sources',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.book),
                  label: 'Manual',
                ),
                NavigationDestination(
                  icon: Icon(Icons.info),
                  label: 'About',
                ),
              ],
            ),
    );
  }
}
