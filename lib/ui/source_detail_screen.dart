import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dictionary_models.dart';
import '../services/dictionary_client.dart';
import '../providers/providers.dart';
import 'package:path/path.dart' as p;

class DictionaryItemViewModel {
  final String url;
  final String name;
  final DictionaryStatus status;
  bool isSelected;

  DictionaryItemViewModel({
    required this.url,
    required this.name,
    required this.status,
    this.isSelected = false,
  });
}

final dictionaryItemsProvider = AutoDisposeAsyncNotifierProviderFamily<DictionaryItemsNotifier, List<DictionaryItemViewModel>, DictionarySource>(() {
  return DictionaryItemsNotifier();
});

class DictionaryItemsNotifier extends AutoDisposeFamilyAsyncNotifier<List<DictionaryItemViewModel>, DictionarySource> {
  @override
  Future<List<DictionaryItemViewModel>> build(DictionarySource arg) async {
    final client = ref.watch(dictionaryClientProvider);
    final isar = ref.watch(isarProvider);
    
    final urls = await client.parseSourceList(arg.url);
    final List<DictionaryItemViewModel> items = [];

    for (final url in urls) {
      final status = await client.getDictionaryStatus(url, isar);
      items.add(DictionaryItemViewModel(
        url: url,
        name: p.basename(url),
        status: status,
        // Smart selection: New or UpdateAvailable selected by default
        isSelected: status == DictionaryStatus.newFile || status == DictionaryStatus.updateAvailable,
      ));
    }
    return items;
  }

  void toggleSelection(int index) {
    final items = state.value;
    if (items != null) {
      final newItems = List<DictionaryItemViewModel>.from(items);
      newItems[index].isSelected = !newItems[index].isSelected;
      state = AsyncData(newItems);
    }
  }

  void selectAll(bool selected) {
    final items = state.value;
    if (items != null) {
      final newItems = items.map((e) {
        e.isSelected = selected;
        return e;
      }).toList();
      state = AsyncData(newItems);
    }
  }
}

class SourceDetailScreen extends ConsumerWidget {
  final DictionarySource source;

  const SourceDetailScreen({super.key, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(dictionaryItemsProvider(source));

    return Scaffold(
      appBar: AppBar(
        title: Text(source.label),
        actions: [
          itemsAsync.when(
            data: (items) => Checkbox(
              value: items.every((e) => e.isSelected),
              tristate: items.any((e) => e.isSelected) && !items.every((e) => e.isSelected),
              onChanged: (val) {
                ref.read(dictionaryItemsProvider(source).notifier).selectAll(val ?? false);
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (err, stack) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: itemsAsync.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              title: Text(item.name),
              subtitle: _getStatusWidget(item.status),
              leading: Icon(
                item.isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: item.isSelected ? Theme.of(context).primaryColor : Colors.grey,
              ),
              trailing: Icon(
                item.status == DictionaryStatus.upToDate
                    ? Icons.check_circle_outline
                    : Icons.download_for_offline_outlined,
                color: _getStatusColor(item.status),
              ),
              onTap: () {
                ref.read(dictionaryItemsProvider(source).notifier).toggleSelection(index);
              },
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: itemsAsync.when(
        data: (items) {
          final selectedCount = items.where((e) => e.isSelected).length;
          return selectedCount > 0
              ? FloatingActionButton.extended(
                  onPressed: () => _startSync(context, ref, items.where((e) => e.isSelected).toList()),
                  label: Text('Download $selectedCount'),
                  icon: const Icon(Icons.sync),
                )
              : null;
        },
        loading: () => null,
        error: (err, stack) => null,
      ),
    );
  }

  Widget _getStatusWidget(DictionaryStatus status) {
    String text;
    Color color;
    switch (status) {
      case DictionaryStatus.newFile:
        text = 'New';
        color = Colors.green;
        break;
      case DictionaryStatus.updateAvailable:
        text = 'Update Available';
        color = Colors.orange;
        break;
      case DictionaryStatus.upToDate:
        text = 'Up to Date';
        color = Colors.grey;
        break;
    }
    return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold));
  }

  Color _getStatusColor(DictionaryStatus status) {
    switch (status) {
      case DictionaryStatus.newFile: return Colors.green;
      case DictionaryStatus.updateAvailable: return Colors.orange;
      case DictionaryStatus.upToDate: return Colors.grey;
    }
  }

  void _startSync(BuildContext context, WidgetRef ref, List<DictionaryItemViewModel> selectedItems) {
    // TODO: Implement actual bulk sync logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Starting sync for ${selectedItems.length} items')),
    );
  }
}
