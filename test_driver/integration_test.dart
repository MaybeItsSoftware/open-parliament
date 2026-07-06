// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      if (data != null && data.containsKey('screenshots')) {
        final Map<String, dynamic> screenshots = data['screenshots'] as Map<String, dynamic>;
        for (final entry in screenshots.entries) {
          final String pathStr = entry.key;
          final String bytesBase64 = entry.value as String;
          final List<int> imageBytes = base64Decode(bytesBase64);
          
          final file = File('$pathStr.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(imageBytes);
          print('Saved high-fidelity screenshot: $pathStr.png (size: ${imageBytes.length} bytes)');
        }
      }
    },
  );
}
