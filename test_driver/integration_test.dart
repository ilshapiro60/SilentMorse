import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes) async {
      final dir = Directory('store_screenshots');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
