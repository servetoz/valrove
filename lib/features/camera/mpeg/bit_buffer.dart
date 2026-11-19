// Port of jsmpeg's BitBuffer (MIT License, (c) 2017 Dominic Szablewski).
import 'dart:math' as math;
import 'dart:typed_data';

enum BitBufferMode { evict, expand }

/// Bit-level reader over a growable byte buffer.
class BitBuffer {
  BitBuffer(int capacity, {this.mode = BitBufferMode.expand})
    : bytes = Uint8List(capacity);

  BitBuffer.wrap(Uint8List data)
    : bytes = data,
      byteLength = data.length,
      mode = BitBufferMode.expand;

  Uint8List bytes;
  int byteLength = 0;

  /// Read position in bits.
  int index = 0;
  final BitBufferMode mode;

  void _resize(int size) {
    final next = Uint8List(size);
    if (byteLength != 0) {
      byteLength = math.min(byteLength, size);
      next.setRange(0, byteLength, bytes);
    }
    bytes = next;
    index = math.min(index, byteLength << 3);
  }

  void _evict(int sizeNeeded) {
    final bytePos = index >> 3;
    final available = bytes.length - byteLength;
    if (index == byteLength << 3 || sizeNeeded > available + bytePos) {
      byteLength = 0;
      index = 0;
      return;
    }
    if (bytePos == 0) return;
    bytes.setRange(0, byteLength - bytePos, bytes, bytePos);
    byteLength -= bytePos;
    index -= bytePos << 3;
  }

  int write(List<Uint8List> buffers) {
    var total = 0;
    for (final b in buffers) {
      total += b.length;
    }
    final available = bytes.length - byteLength;
    if (total > available) {
      if (mode == BitBufferMode.expand) {
        _resize(math.max(bytes.length * 2, byteLength + total));
      } else {
        _evict(total);
        if (total > bytes.length - byteLength) _resize(byteLength + total);
      }
    }
    for (final b in buffers) {
      bytes.setRange(byteLength, byteLength + b.length, b);
      byteLength += b.length;
    }
    return total;
  }

  int _byte(int i) =>
      i < byteLength ? bytes[i] : (i < bytes.length ? bytes[i] : 0);

  /// Moves past the next start code (00 00 01 xx) and returns `xx`, or -1.
  int findNextStartCode() {
    for (var i = (index + 7) >> 3; i < byteLength; i++) {
      if (bytes[i] == 0x00 && _byte(i + 1) == 0x00 && _byte(i + 2) == 0x01) {
        index = (i + 4) << 3;
        return _byte(i + 3);
      }
    }
    index = byteLength << 3;
    return -1;
  }

  int findStartCode(int code) {
    while (true) {
      final current = findNextStartCode();
      if (current == code || current == -1) return current;
    }
  }

  bool nextBytesAreStartCode() {
    final i = (index + 7) >> 3;
    return i >= byteLength ||
        (bytes[i] == 0x00 && _byte(i + 1) == 0x00 && _byte(i + 2) == 0x01);
  }

  int peek(int count) {
    var offset = index;
    var value = 0;
    while (count > 0) {
      final currentByte = _byte(offset >> 3);
      final remaining = 8 - (offset & 7);
      final read = remaining < count ? remaining : count;
      final shift = remaining - read;
      final mask = 0xff >> (8 - read);
      value = (value << read) | ((currentByte & (mask << shift)) >> shift);
      offset += read;
      count -= read;
    }
    return value;
  }

  int read(int count) {
    final value = peek(count);
    index += count;
    return value;
  }

  void skip(int count) => index += count;

  void rewind(int count) => index = math.max(index - count, 0);

  bool has(int count) => ((byteLength << 3) - index) >= count;
}
