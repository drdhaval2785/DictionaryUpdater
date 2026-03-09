import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
          return Markdown(
            data: snapshot.data ?? 'No guide found.',
            onTapLink: (text, href, title) {
              if (href != null) {
                final String url;
                if (Platform.isIOS && href.contains('apps.apple.com')) {
                  url = href.replaceFirst('https://apps.apple.com', 'itms-apps://itunes.apple.com');
                } else {
                  url = href;
                }
                final urlFinal = url;
                launchUrl(
                  Uri.parse(urlFinal),
                  mode: LaunchMode.externalApplication,
                ).then((success) {
                  if (!success && context.mounted) {
                    Clipboard.setData(ClipboardData(text: href));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open link. URL copied to clipboard.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }).catchError((e) {
                  if (context.mounted) {
                    Clipboard.setData(ClipboardData(text: href));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open link. URL copied to clipboard.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                });
              }
            },
          );
        },
      ),
    );
  }
}
