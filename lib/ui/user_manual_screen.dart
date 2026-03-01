import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import '../providers/providers.dart';

class UserManualScreen extends ConsumerWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider);
    final version = packageInfo.version;
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Manual'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Center(
              child: Text('v$version', style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('USER_GUIDE.md'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading manual: ${snapshot.error}'));
          }
          return Markdown(data: snapshot.data ?? 'No guide found.');
        },
      ),
    );
  }
}
