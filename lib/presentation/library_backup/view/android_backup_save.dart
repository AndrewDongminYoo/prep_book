import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('prep_book/backup_save');

/// Saves a backup through the Android document picker without channeling bytes.
Future<bool> saveAndroidBackup({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  final directory = await Directory.systemTemp.createTemp('prep-book-save-');
  try {
    final file = File('${directory.path}/backup.prepbook');
    await file.writeAsBytes(bytes, flush: true);
    return await _channel.invokeMethod<bool>('saveBackup', {
          'path': file.path,
          'fileName': suggestedName,
        }) ??
        false;
  } finally {
    await directory.delete(recursive: true);
  }
}
