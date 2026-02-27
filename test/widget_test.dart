import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdu/main.dart';
import 'package:sdu/providers/providers.dart';
import 'package:sdu/models/dictionary_models.dart';
import 'package:dio/dio.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    // Initialize mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Override sourcesProvider to avoid Isar dependency in smoke test
          sourcesProvider.overrideWith(() => _MockSourcesNotifier()),
          // Override repoIndexProvider to avoid real network calls and return immediately
          repoIndexProvider.overrideWith((ref) => Future.value('')),
          // Override dioProvider to avoid real network calls
          dioProvider.overrideWithValue(Dio(BaseOptions(connectTimeout: const Duration(milliseconds: 1)))),
        ],
        child: const DictionaryUpdaterApp(),
      ),
    );

    // Initial build. pump() is needed to let the first microtasks and initState work finish.
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Since we returned an empty string immediately for the repo index,
    // _loadIndex finishes instantly and doesn't trigger _fetchAll.
    // This cleans up all timers.
  });
}

class _MockSourcesNotifier extends SourcesNotifier {
  @override
  Future<List<DictionarySource>> build() async {
    return [];
  }
}
