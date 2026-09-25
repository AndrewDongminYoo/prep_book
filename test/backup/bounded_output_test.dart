import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/backup/bounded_output.dart';

void main() {
  final tooLarge = throwsA(isA<ArchiveEntryTooLarge>());

  test('single bytes fill the output exactly to its limit', () {
    final output = BoundedOutputMemoryStream(2)
      ..writeByte(1)
      ..writeByte(2);

    expect(() => output.writeByte(3), tooLarge);
    expect(output.getBytes(), [1, 2]);
  });

  test('a block write is refused whole when it would pass the limit', () {
    final output = BoundedOutputMemoryStream(4)..writeBytes([1, 2, 3]);

    expect(() => output.writeBytes([4, 5]), tooLarge);
    output.writeBytes([4, 5, 6], length: 1);

    expect(() => output.writeBytes([7, 8, 9], length: 1), tooLarge);
    expect(output.getBytes(), [1, 2, 3, 4]);
  });

  test('a stream write is refused whole when it would pass the limit', () {
    final output = BoundedOutputMemoryStream(3)..writeStream(InputMemoryStream(Uint8List.fromList([1, 2])));

    expect(
      () => output.writeStream(InputMemoryStream(Uint8List.fromList([3, 4]))),
      tooLarge,
    );
    output.writeStream(InputMemoryStream(Uint8List.fromList([3])));

    expect(output.getBytes(), [1, 2, 3]);
    expect(output.maxBytes, 3);
  });
}
