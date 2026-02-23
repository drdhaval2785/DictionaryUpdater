import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_center_screen.dart';
import 'settings_screen.dart';
import 'user_manual_screen.dart';
import 'about_us_screen.dart';
import 'support_screen.dart';
import 'add_dictionary_dialog.dart';
import 'source_expansion_panel.dart';
import '../providers/providers.dart';

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
    const SupportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isWide = width > 900;

    final sourcesAsync = ref.watch(sourcesProvider);
    final allSources = sourcesAsync.valueOrNull ?? [];

    // listen needs an explicit type argument so that `next` is treated as
    // `List<String>` rather than `Object?` (which was causing the earlier
    // "getter 'isNotEmpty' isn't defined for Object?" error).
    ref.listen<List<String>>(failedResourcesProvider, (prev, next) {
      if (next.isNotEmpty) {
        _showFailureDialog(context, ref, next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stardict Dictionary Updater',
          overflow: TextOverflow.ellipsis,
        ),
        actions: _selectedIndex == 0
            ? [
                // Minimalist Settings icon would be redundant here since Rail is on left
              ]
            : null,
        bottom: _selectedIndex == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(80),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Add Dictionary'),
                        onPressed: () => showAddDictionaryDialog(context, ref),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Check for Updates'),
                            onPressed: () {
                              ref.invalidate(sourcesProvider);
                              for (final s in allSources) {
                                ref.invalidate(sourceItemsProvider(s));
                              }
                              ref
                                  .read(lastCheckedAllProvider.notifier)
                                  .updateTimestamp();
                            },
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              final lastChecked =
                                  ref.watch(lastCheckedAllProvider);
                              if (lastChecked == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 2, left: 4),
                                child: Text(
                                  'Last checked: ${_fmtDt(lastChecked)}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: isWide,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: isWide
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
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
              NavigationRailDestination(
                icon: Icon(Icons.favorite),
                selectedIcon: Icon(Icons.favorite_border),
                label: Text('Support Us'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  String _fmtDt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showFailureDialog(BuildContext context, WidgetRef ref, List<String> failures) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Issues'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not connect to the following resources while updating:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              // `SizedBox` no longer supports `maxHeight`; use a fixed height
              // constraint instead. The dialog was only ever meant to be a
              // limited scrollable area.
              height: 200,
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: failures.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${failures[index]}', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The user is requested to manually verify whether the required resource is available for download or not.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(failedResourcesProvider.notifier).state = [];
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
