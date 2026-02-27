import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_center_screen.dart';
import 'user_manual_screen.dart';
import 'about_us_screen.dart';
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
    const UserManualScreen(),
    const AboutUsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);
    final allSources = sourcesAsync.valueOrNull ?? [];

    ref.listen<List<String>>(failedResourcesProvider, (prev, next) {
      if (next.isNotEmpty) {
        _showFailureDialog(context, ref, next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dictionary Updater',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18),
        ),
        bottom: _selectedIndex == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Add'),
                          onPressed: () => showAddDictionaryDialog(context, ref),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
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
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_book, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Dictionary Updater',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
            _buildDrawerItem(0, Icons.sync, 'Sources'),
            _buildDrawerItem(1, Icons.book, 'Manual'),
            _buildDrawerItem(2, Icons.info, 'About Us'),
            const Spacer(),
            Consumer(
              builder: (context, ref, child) {
                final lastChecked = ref.watch(lastCheckedAllProvider);
                if (lastChecked == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Last checked: ${_fmtDt(lastChecked)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : null),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        Navigator.pop(context); // Close drawer
      },
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
        title: const Text('Processing Issues'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The following resources could not be processed:',
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
