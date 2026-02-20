import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdu/main.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: This test might fail if it requires complex initialization (Isar/SharedPreferences)
    // but we'll keep it simple for now as a placeholder.
    await tester.pumpWidget(const StarDictManagerApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
