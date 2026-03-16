import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Capture store screenshots', (tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // If we see auth screen (no user), capture and exit
    if (find.text('Continue with Google').evaluate().isNotEmpty ||
        find.text('Continue with Apple').evaluate().isNotEmpty) {
      await binding.takeScreenshot('00-auth');
      return;
    }

    // 1. Contacts screen (main view when signed in)
    await binding.takeScreenshot('01-contacts');
    await tester.pumpAndSettle();

    // 2. Open first chat
    await tester.tap(find.text('... --- ...').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.takeScreenshot('02-chat');
    await tester.pumpAndSettle();

    // 3. Go back and open Settings
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.takeScreenshot('03-settings');
  });
}
