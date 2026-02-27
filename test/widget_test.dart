import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdu/main.dart';
import 'package:sdu/providers/providers.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    // Initialize mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    // Wrap in ProviderScope to satisfy riverpod dependencies
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // We don't override isarProvider yet as it might require a real/mock instance
          // but we'll see if the initial build passes without it or with a late override.
        ],
        child: const DictionaryUpdaterApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
