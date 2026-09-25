import 'package:archive/archive.dart';

/// Thrown when an archive entry grows past the size it is allowed.
final class ArchiveEntryTooLarge implements Exception {
  /// Creates the bound failure.
  const new();
}

/// An in-memory `archive` output that refuses to grow past [maxBytes].
///
/// The bzip2 decoder in `archive` 4.3.0 writes one byte at a time, so only
/// [writeByte] is reached today. The bulk writes are bounded as well, so a
/// release that writes in blocks cannot inflate a lying entry into memory
/// before anything checks it.
final class BoundedOutputMemoryStream extends OutputMemoryStream {
  /// Creates an empty output that holds at most [maxBytes].
  new(this.maxBytes);

  /// The most bytes this output accepts.
  final int maxBytes;

  @override
  void writeByte(int value) {
    _checkAdditionalBytes(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final writeLength = length ?? bytes.length;
    _checkAdditionalBytes(writeLength);
    super.writeBytes(bytes, length: writeLength);
  }

  @override
  void writeStream(InputStream stream) {
    _checkAdditionalBytes(stream.length);
    super.writeStream(stream);
  }

  void _checkAdditionalBytes(int count) {
    if (count > maxBytes - length) throw const ArchiveEntryTooLarge();
  }
}
