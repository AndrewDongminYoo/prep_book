import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('prep_book/backup_save');

/// Saves a backup through the Android document picker without channeling bytes.
///
/// [content] is streamed to an app-private temporary file whose path is all
/// the channel carries; the native side copies it to the chosen document.
Future<bool> saveAndroidBackup({
  required String suggestedName,
  required Stream<List<int>> content,
}) async {
  final directory = await Directory.systemTemp.createTemp('prep-book-save-');
  try {
    final file = File('${directory.path}/backup.prepbook');
    final output = await file.open(mode: FileMode.write);
    try {
      await for (final chunk in content) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    return await _channel.invokeMethod<bool>('saveBackup', {
          'path': file.path,
          'fileName': suggestedName,
        }) ??
        false;
  } finally {
    await directory.delete(recursive: true);
  }
}
