import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';

class DownloadInfoWidget extends ConsumerWidget {
  const DownloadInfoWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageService = ref.read(storageServiceProvider);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<String>(
          future: storageService.getStoragePathDisplay(),
          builder: (context, snapshot) {
            final path = snapshot.data ?? 'Loading folder path...';
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.folder_special_outlined, size: 14, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Download Directory: $path',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            const url = 'https://apps.apple.com/in/app/hdict/id6759493062';
            var uri = Uri.parse(url);
            if (Platform.isIOS) {
              uri = Uri.parse(url.replaceFirst('https://apps.apple.com', 'itms-apps://itunes.apple.com'));
            }
            launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            ).then((success) {
              if (!success && context.mounted) {
                Clipboard.setData(const ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open App Store. Link copied to clipboard.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }).catchError((e) {
              if (context.mounted) {
                Clipboard.setData(const ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open App Store. Link copied to clipboard.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            });
          },
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, size: 14, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Use any dictionary reader (e.g. ',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                    children: [
                      TextSpan(
                        text: 'HDICT',
                        style: TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(text: ')'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
