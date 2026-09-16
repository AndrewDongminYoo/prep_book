import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/presentation/library_backup/view/android_backup_save.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('prep_book/backup_save');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'sends a temporary file path rather than bytes and removes it',
    () async {
      String? sourcePath;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveBackup');
        final arguments = Map<String, Object?>.from(call.arguments as Map);
        expect(arguments.keys, unorderedEquals(['path', 'fileName']));
        expect(arguments['fileName'], 'library.prepbook');
        sourcePath = arguments['path']! as String;
        expect(await File(sourcePath!).readAsBytes(), [1, 2, 3]);
        return true;
      });

      expect(
        await saveAndroidBackup(
          suggestedName: 'library.prepbook',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        isTrue,
      );
      expect(sourcePath, isNotNull);
      expect(File(sourcePath!).existsSync(), isFalse);
      expect(File(sourcePath!).parent.existsSync(), isFalse);
    },
  );

  test('removes the temporary file after cancellation', () async {
    String? sourcePath;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sourcePath = (call.arguments as Map)['path'] as String;
      return false;
    });

    expect(
      await saveAndroidBackup(
        suggestedName: 'library.prepbook',
        bytes: Uint8List.fromList([1]),
      ),
      isFalse,
    );
    expect(File(sourcePath!).existsSync(), isFalse);
  });

  test('removes the temporary file after a channel failure', () async {
    String? sourcePath;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sourcePath = (call.arguments as Map)['path'] as String;
      throw PlatformException(code: 'save_failed');
    });

    await expectLater(
      saveAndroidBackup(
        suggestedName: 'library.prepbook',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(File(sourcePath!).existsSync(), isFalse);
  });
}
