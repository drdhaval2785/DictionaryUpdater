import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../providers/providers.dart';

// ─── Data model ────────────────────────────────────────────────────────────────

/// A node in the dictionaryIndices.md hierarchy.
/// Level: 2 = ##, 3 = ###, 4 = ####
class _IndexNode {
  _IndexNode({
    required this.level,
    required this.title,
    this.tarsUrl,
    this.parent,
  });

  final int level; // 2, 3, or 4
  final String title;
  final String? tarsUrl; // non-null for leaf nodes (tars.MD links)
  final _IndexNode? parent;
  final List<_IndexNode> children = [];

  bool isSelected = false;

  /// Returns the sanitized nested folder path for this node, e.g.
  /// "sa_संस्कृतम्/Basic/En"
  String folderPath() {
    final segments = <String>[];
    _IndexNode? cur = parent;
    while (cur != null) {
      segments.insert(0, _sanitize(cur.title));
      cur = cur.parent;
    }
    if (tarsUrl == null) segments.add(_sanitize(title));
    return p.joinAll(segments.isEmpty ? [_sanitize(title)] : segments);
  }

  static String _sanitize(String s) =>
      s.trim().replaceAll(RegExp(r'[\s<>:"/\\|?*]+'), '_');
}

/// Metadata extracted from a single dictionary archive filename.
class _DictEntry {
  _DictEntry({
    required this.url,
    required this.name,
    required this.date,
    required this.sizeMb,
    required this.folderPath,
  });

  final String url;
  final String name;
  final String date;
  final String sizeMb;
  final String folderPath; // source label / nested folder

  bool isSelected = false;
}

// ─── Parsing helpers ────────────────────────────────────────────────────────────

/// Parses the raw Markdown text into a list of root-level (_IndexNode level 2)
/// nodes, each containing ###/#### children and tars.MD leaf links.
List<_IndexNode> _parseIndices(String markdown) {
  final lines = markdown.split('\n');
  _IndexNode? h2, h3, h4;
  final roots = <_IndexNode>[];

  // Matches <https://...tars.MD> or <https://...tars_external.MD>
  // but NOT lines starting with "Disabled:"
  final urlRe = RegExp(r'<(https?://\S+\.MD)>', caseSensitive: false);

  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#### ')) {
      final title = line.substring(5).trim();
      h4 = _IndexNode(level: 4, title: title, parent: h3 ?? h2);
      (h3 ?? h2)?.children.add(h4);
    } else if (line.startsWith('### ')) {
      final title = line.substring(4).trim();
      h3 = _IndexNode(level: 3, title: title, parent: h2);
      h4 = null;
      h2?.children.add(h3);
    } else if (line.startsWith('## ')) {
      final title = line.substring(3).trim();
      h2 = _IndexNode(level: 2, title: title);
      h3 = h4 = null;
      roots.add(h2);
    } else if (!line.startsWith('Disabled:')) {
      final m = urlRe.firstMatch(line);
      if (m != null) {
        final url = m.group(1)!;
        final parent = h4 ?? h3 ?? h2;
        if (parent != null) {
          final leaf = _IndexNode(
            level: parent.level + 1,
            title: url.split('/').reversed.take(2).toList().reversed.join('/'),
            tarsUrl: url,
            parent: parent,
          );
          parent.children.add(leaf);
        }
      }
    }
  }
  return roots;
}

/// Parses a tars.MD file content into individual dictionary file URLs, grouped
/// ready to display. Returns raw archive URLs found.
List<String> _parseTarsMd(String content) {
  final archiveExt =
      r'\.(?:tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz|txz|tar\.lzma|tlz|tar\.zst|tzst|zip|7z|rar|bz2|xz|lzma|zst|dz)';
  final re = RegExp(r'https?://\S+?' + archiveExt, caseSensitive: false);
  return re.allMatches(content).map((m) => m.group(0)!).toList();
}

/// Extracts display metadata from a URL like:
///   .../dictname_20240101_120000_12MB.tar.gz
_DictEntry _parseEntry(String url, String folderPath) {
  final filename = url.split('/').last;
  // pattern: name_YYYYMMDD_HHMMSS_NNMb.ext  (size may be decimal like 1.5MB)
  final re = RegExp(
      r'^(.+?)_(\d{8})_(\d{6})_([\d.]+)MB\.(.+)$',
      caseSensitive: false);
  final m = re.firstMatch(filename);
  if (m != null) {
    final rawDate = m.group(2)!; // 20240101
    final date = '${rawDate.substring(0, 4)}-${rawDate.substring(4, 6)}-${rawDate.substring(6, 8)}';
    return _DictEntry(
      url: url,
      name: m.group(1)!.replaceAll('_', ' '),
      date: date,
      sizeMb: '${m.group(4)} MB',
      folderPath: folderPath,
    );
  }
  // Fallback
  return _DictEntry(
    url: url,
    name: filename,
    date: '',
    sizeMb: '',
    folderPath: folderPath,
  );
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class IndicDictBrowserScreen extends StatefulWidget {
  const IndicDictBrowserScreen({super.key, required this.ref});

  /// Riverpod ref passed from the parent so we can call addSource.
  final WidgetRef ref;

  @override
  State<IndicDictBrowserScreen> createState() => _IndicDictBrowserScreenState();
}

class _IndicDictBrowserScreenState extends State<IndicDictBrowserScreen> {
  static const _indicesUrl =
      'https://github.com/indic-dict/stardict-index/releases/download/current/dictionaryIndices.md';

  // Step 1 state
  List<_IndexNode> _roots = [];
  bool _loadingIndex = true;
  String? _indexError;

  // Step 2 state
  bool _step2 = false;
  bool _fetchingDicts = false;
  String? _fetchError;
  // Map from tarsUrl → list of DictEntry
  final Map<String, List<_DictEntry>> _dictsBySource = {};
  // For display: keep track of which source label a tarsUrl belongs to
  final Map<String, String> _sourceLabel = {};

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final dio = Dio();
      final resp = await dio.get<String>(_indicesUrl);
      final roots = _parseIndices(resp.data ?? '');
      if (mounted) setState(() { _roots = roots; _loadingIndex = false; });
    } catch (e) {
      if (mounted) setState(() { _indexError = e.toString(); _loadingIndex = false; });
    }
  }

  // Collect selected leaf nodes (tars.MD links)
  List<_IndexNode> _selectedLeaves() {
    final out = <_IndexNode>[];
    void walk(_IndexNode n) {
      if (n.tarsUrl != null && n.isSelected) { out.add(n); }
      for (final c in n.children) { walk(c); }
    }
    for (final r in _roots) { walk(r); }
    return out;
  }

  Future<void> _fetchSelected() async {
    final leaves = _selectedLeaves();
    if (leaves.isEmpty) return;
    setState(() { _fetchingDicts = true; _fetchError = null; _step2 = true; _dictsBySource.clear(); _sourceLabel.clear(); });

    final dio = Dio();
    for (final leaf in leaves) {
      final url = leaf.tarsUrl!;
      final folder = leaf.parent != null ? leaf.parent!.folderPath() : _IndexNode._sanitize(leaf.title);
      try {
        final resp = await dio.get<String>(url);
        final archiveUrls = _parseTarsMd(resp.data ?? '');
        final entries = archiveUrls.map((u) => _parseEntry(u, folder)).toList();
        _dictsBySource[url] = entries;
        _sourceLabel[url] = leaf.title;
      } catch (_) {
        _dictsBySource[url] = [];
        _sourceLabel[url] = leaf.title;
      }
    }
    if (mounted) setState(() { _fetchingDicts = false; });
  }

  List<_DictEntry> get _selectedDicts {
    return _dictsBySource.values.expand((l) => l).where((e) => e.isSelected).toList();
  }

  Future<void> _addToDownloadQueue() async {
    final selected = _selectedDicts;
    if (selected.isEmpty) return;

    final notifier = widget.ref.read(sourcesProvider.notifier);
    for (final entry in selected) {
      await notifier.addSource(entry.url, entry.folderPath);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${selected.length} dictionary source(s)')),
      );
      Navigator.pop(context);
    }
  }

  // ─── Tree-selection helpers ─────────────────────────────────────────────────

  void _setNodeSelected(_IndexNode node, bool val) {
    node.isSelected = val;
    for (final c in node.children) { _setNodeSelected(c, val); }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step2 ? 'Select Dictionaries' : 'Browse Indic-dicts'),
        leading: _step2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _step2 = false; }),
              )
            : null,
      ),
      body: _step2 ? _buildStep2() : _buildStep1(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildStep1() {
    if (_loadingIndex) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading Indic-dict index…'),
        ],
      ));
    }
    if (_indexError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_indexError!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () { setState(() { _loadingIndex = true; _indexError = null; }); _loadIndex(); }, child: const Text('Retry')),
        ]),
      ));
    }
    return Column(children: [
      Container(
        color: Colors.indigo.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 16, color: Colors.indigo),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Select one or more tars.MD sources, then tap "Fetch Selected" to browse individual dictionaries.',
            style: TextStyle(fontSize: 12, color: Colors.indigo),
          )),
        ]),
      ),
      Expanded(child: ListView(
        children: _roots.map((r) => _H2Tile(node: r, onChanged: (v) {
          setState(() { _setNodeSelected(r, v ?? false); });
        })).toList(),
      )),
    ]);
  }

  Widget _buildStep2() {
    if (_fetchingDicts) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Fetching dictionary lists…'),
      ]));
    }
    if (_fetchError != null) {
      return Center(child: Text(_fetchError!));
    }
    if (_dictsBySource.isEmpty) {
      return const Center(child: Text('No dictionaries found.'));
    }

    final items = <Widget>[];
    _dictsBySource.forEach((srcUrl, dicts) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          const Icon(Icons.source, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(child: Text(
            _sourceLabel[srcUrl] ?? srcUrl,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          )),
        ]),
      ));
      if (dicts.isEmpty) {
        items.add(const Padding(
          padding: EdgeInsets.only(left: 32, bottom: 8),
          child: Text('No dictionaries found in this source.', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ));
      }
      for (final entry in dicts) {
        items.add(CheckboxListTile(
          value: entry.isSelected,
          dense: true,
          title: Text(entry.name, style: const TextStyle(fontSize: 14)),
          subtitle: entry.date.isNotEmpty
              ? Text('${entry.date}  •  ${entry.sizeMb}', style: const TextStyle(fontSize: 12))
              : null,
          secondary: entry.sizeMb.isNotEmpty
              ? Chip(
                  label: Text(entry.sizeMb, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              : null,
          onChanged: (v) => setState(() { entry.isSelected = v ?? false; }),
        ));
      }
    });

    return ListView(children: items);
  }

  Widget _buildBottomBar() {
    if (_step2) {
      final count = _selectedDicts.length;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: count > 0 ? _addToDownloadQueue : null,
            icon: const Icon(Icons.add_task),
            label: Text(count > 0 ? 'Add $count to Download Queue' : 'Select dictionaries above'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      );
    }

    final leafCount = _selectedLeaves().length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton.icon(
          onPressed: leafCount > 0
              ? () async { await _fetchSelected(); }
              : null,
          icon: _fetchingDicts
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.search),
          label: Text(leafCount > 0 ? 'Fetch Selected ($leafCount source${leafCount == 1 ? '' : 's'})' : 'Select sources above'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Hierarchy tiles ────────────────────────────────────────────────────────────

class _H2Tile extends StatefulWidget {
  const _H2Tile({required this.node, required this.onChanged});
  final _IndexNode node;
  final ValueChanged<bool?> onChanged;
  @override
  State<_H2Tile> createState() => _H2TileState();
}

class _H2TileState extends State<_H2Tile> {
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final leaves = <_IndexNode>[];
    void collect(_IndexNode n) {
      if (n.tarsUrl != null) {
        leaves.add(n);
      } else {
        for (final c in n.children) { collect(c); }
      }
    }
    collect(node);
    final allOn = leaves.isNotEmpty && leaves.every((l) => l.isSelected);
    final anyOn = leaves.any((l) => l.isSelected);

    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: allOn ? true : (anyOn ? null : false),
        onChanged: (v) {
          setState(() {
            _setAll(node, v ?? false);
          });
          widget.onChanged(v);
        },
      ),
      title: Text(node.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: node.children.map((child) {
        if (child.tarsUrl != null) {
          return _LeafTile(node: child, onChanged: (_) => setState(() {}));
        }
        return _H3Tile(node: child, onChanged: (_) => setState(() {}));
      }).toList(),
    );
  }

  void _setAll(_IndexNode n, bool v) {
    n.isSelected = v;
    for (final c in n.children) { _setAll(c, v); }
  }
}

class _H3Tile extends StatefulWidget {
  const _H3Tile({required this.node, required this.onChanged});
  final _IndexNode node;
  final ValueChanged<bool?> onChanged;
  @override
  State<_H3Tile> createState() => _H3TileState();
}

class _H3TileState extends State<_H3Tile> {
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final leaves = <_IndexNode>[];
    void collect(_IndexNode n) {
      if (n.tarsUrl != null) {
        leaves.add(n);
      } else {
        for (final c in n.children) { collect(c); }
      }
    }
    collect(node);
    final allOn = leaves.isNotEmpty && leaves.every((l) => l.isSelected);
    final anyOn = leaves.any((l) => l.isSelected);

    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: allOn ? true : (anyOn ? null : false),
        onChanged: (v) {
          setState(() { _setAll(node, v ?? false); });
          widget.onChanged(v);
        },
      ),
      title: Text(node.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: node.children.map((child) {
        if (child.tarsUrl != null) {
          return _LeafTile(node: child, onChanged: (_) => setState(() {}));
        }
        return _H3Tile(node: child, onChanged: (_) => setState(() {}));
      }).toList(),
    );
  }

  void _setAll(_IndexNode n, bool v) {
    n.isSelected = v;
    for (final c in n.children) { _setAll(c, v); }
  }
}

class _LeafTile extends StatefulWidget {
  const _LeafTile({required this.node, required this.onChanged});
  final _IndexNode node;
  final ValueChanged<bool?> onChanged;
  @override
  State<_LeafTile> createState() => _LeafTileState();
}

class _LeafTileState extends State<_LeafTile> {
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return CheckboxListTile(
      dense: true,
      value: node.isSelected,
      title: Text(node.title, style: const TextStyle(fontSize: 13)),
      secondary: const Icon(Icons.description_outlined, size: 18, color: Colors.grey),
      onChanged: (v) {
        setState(() { node.isSelected = v ?? false; });
        widget.onChanged(v);
      },
    );
  }
}
