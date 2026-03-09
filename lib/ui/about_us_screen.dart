import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';

class AboutUsScreen extends ConsumerWidget {
  const AboutUsScreen({super.key});

  Future<void> _launchUrl(String urlString, BuildContext context) async {
    var urlStringFinal = urlString;
    if (Platform.isIOS && urlStringFinal.contains('apps.apple.com')) {
      urlStringFinal = urlStringFinal.replaceFirst('https://apps.apple.com', 'itms-apps://itunes.apple.com');
    }
    final Uri url = Uri.parse(urlStringFinal);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (context.mounted) {
        await Clipboard.setData(ClipboardData(text: urlString));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open link. URL copied to clipboard.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider);
    final version = packageInfo.version;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(
            'assets/dict_up.png',
            height: 120,
          ),
          const SizedBox(height: 24),
          Text(
            'Dictionary Updater',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Version $version',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'Vibe coded by Dr. Dhaval Patel (drdhaval2785@gmail.com).\n\nDedicated to lexicographers across ages and places.',
                  style: TextStyle(fontSize: 16, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'For any issue or feature request, please feel free to reach out to us at',
                  style: TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchUrl('https://github.com/drdhaval2785/DictionaryUpdater', context),
                  child: const Text(
                    'https://github.com/drdhaval2785/DictionaryUpdater',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
