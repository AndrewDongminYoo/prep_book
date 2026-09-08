import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/sqflite/timestamps.dart';

void main() {
  // The instant `toIso8601String` shortens: `microsecond` is zero, so it
  // emits the millisecond triplet and stops.
  final wholeMillisecond = DateTime.utc(2026, 9, 7, 12, 0, 0, 1);

  // The same millisecond, one microsecond later, which `toIso8601String`
  // writes three characters longer.
  final oneMicrosecondLater = DateTime.utc(2026, 9, 7, 12, 0, 0, 1, 1);

  // The width, not the suffix, is what a text `ORDER BY` depends on. Naming
  // the exact expected string rather than matching a pattern also pins the
  // padding to the millisecond's own place: appending the triplet in the
  // wrong position would still produce a same-width string.
  test('a whole-millisecond instant is stored with a microsecond triplet', () {
    expect(wholeMillisecond.microsecond, 0);
    expect(wholeMillisecond.toIso8601String(), '2026-09-07T12:00:00.001Z');

    expect(
      timestampToStorage(wholeMillisecond),
      '2026-09-07T12:00:00.001000Z',
    );
  });

  test('an instant carrying microseconds is stored unchanged', () {
    expect(oneMicrosecondLater.microsecond, 1);
    expect(
      timestampToStorage(oneMicrosecondLater),
      '2026-09-07T12:00:00.001001Z',
    );
  });

  // The property the ordering depends on, stated directly: whichever of the
  // two branches ran, the two results have to be comparable as text, which
  // they are only while they are the same width.
  test('both forms are stored at the same width', () {
    expect(
      timestampToStorage(wholeMillisecond).length,
      timestampToStorage(oneMicrosecondLater).length,
    );
  });

  // Lexical order and chronological order agree once the width is fixed.
  // This is the property `ProductionRunRepository.listSummaries` orders on,
  // asserted on the encoding alone so a failure points here rather than at
  // a query.
  test('lexical order follows chronological order across the two forms', () {
    expect(oneMicrosecondLater.isAfter(wholeMillisecond), isTrue);
    expect(
      timestampToStorage(wholeMillisecond).compareTo(
        timestampToStorage(oneMicrosecondLater),
      ),
      lessThan(0),
    );
  });

  // Padding must not change the instant. `isAtSameMomentAs`, never `==`:
  // `DateTime`'s equality includes the `isUtc` flag, so a correct round trip
  // of a local value would fail an `==` for a reason that has nothing to do
  // with the encoding.
  test('a padded value parses back to the same instant', () {
    final parsed = DateTime.parse(timestampToStorage(wholeMillisecond));

    expect(parsed.isAtSameMomentAs(wholeMillisecond), isTrue);
    expect(parsed.isUtc, isTrue);
  });

  // The `.toUtc()` this function absorbed from its three call sites.
  // `toIso8601String` emits the `Z` from the `isUtc` flag rather than from a
  // zone offset, so a runner whose local zone is UTC still fails this
  // without the conversion: `local` is not a UTC `DateTime` there either.
  test('a local value is stored as UTC', () {
    final local = DateTime(2026, 9, 7, 21, 30);
    expect(local.isUtc, isFalse);

    final stored = timestampToStorage(local);

    expect(stored, endsWith('Z'));
    expect(DateTime.parse(stored).isAtSameMomentAs(local), isTrue);
    expect(stored.length, timestampToStorage(oneMicrosecondLater).length);
  });
}
