import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final output = Directory('build/validation')..createSync(recursive: true);
    for (final entry in (data?['screenshots'] as Map? ?? {}).entries) {
      File(
        '${output.path}/${entry.key}.png',
      ).writeAsBytesSync(base64Decode(entry.value as String));
    }
    File('${output.path}/windows-integration.json').writeAsStringSync(
      jsonEncode({
        'stages': data?['stages'],
        'nativeProbe': data?['nativeProbe'],
      }),
    );
  },
);
