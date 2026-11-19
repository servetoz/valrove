// Port of jsmpeg's MPEG-TS demuxer (MIT License, (c) 2017 Dominic Szablewski).
import 'dart:typed_data';

import 'bit_buffer.dart';

typedef PesSink = void Function(double pts, List<Uint8List> buffers);

class _PesPacket {
  _PesPacket(this.sink);

  final PesSink sink;
  int currentLength = 0;
  int totalLength = 0;
  double pts = 0;
  List<Uint8List> buffers = [];
}

/// Splits an MPEG transport stream into PES packets per stream id.
class TsDemuxer {
  static const videoStream = 0xE0;

  final Map<int, int> _pidsToStreamIds = {};
  final Map<int, _PesPacket> _pes = {};
  Uint8List? _leftover;
  late BitBuffer _bits;

  /// Like jsmpeg: an adaptation field with stuffing on a non-start packet
  /// marks the end of a video frame, so frames are delivered without
  /// waiting for the next packet.
  bool guessVideoFrameEnd = true;

  void connect(int streamId, PesSink sink) => _pes[streamId] = _PesPacket(sink);

  void write(Uint8List buffer) {
    final left = _leftover;
    if (left != null) {
      _bits = BitBuffer(left.length + buffer.length)..write([left, buffer]);
    } else {
      _bits = BitBuffer.wrap(buffer);
    }
    while (_bits.has(188 << 3) && _parsePacket()) {}
    final leftoverCount = _bits.byteLength - (_bits.index >> 3);
    _leftover = leftoverCount > 0
        ? Uint8List.fromList(
            Uint8List.sublistView(
              _bits.bytes,
              _bits.index >> 3,
              _bits.byteLength,
            ),
          )
        : null;
  }

  bool _parsePacket() {
    if (_bits.read(8) != 0x47) {
      if (!_resync()) return false;
    }
    final end = (_bits.index >> 3) + 187;
    _bits.skip(1); // transport error
    final payloadStart = _bits.read(1) == 1;
    _bits.skip(1); // priority
    final pid = _bits.read(13);
    _bits.skip(2); // scrambling
    final adaptationField = _bits.read(2);
    _bits.skip(4); // continuity counter

    var streamId = _pidsToStreamIds[pid];
    if (payloadStart && streamId != null) {
      final pi = _pes[streamId];
      if (pi != null && pi.currentLength > 0) _complete(pi);
    }

    if ((adaptationField & 0x1) != 0) {
      if ((adaptationField & 0x2) != 0) {
        final adaptationFieldLength = _bits.read(8);
        _bits.skip(adaptationFieldLength << 3);
      }
      if (payloadStart && _bits.nextBytesAreStartCode()) {
        _bits.skip(24);
        streamId = _bits.read(8);
        _pidsToStreamIds[pid] = streamId;
        final packetLength = _bits.read(16);
        _bits.skip(8);
        final ptsDtsFlag = _bits.read(2);
        _bits.skip(6);
        final headerLength = _bits.read(8);
        final payloadBeginIndex = _bits.index + (headerLength << 3);
        final pi = _pes[streamId];
        if (pi != null) {
          var pts = 0.0;
          if ((ptsDtsFlag & 0x2) != 0) {
            _bits.skip(4);
            final p3230 = _bits.read(3);
            _bits.skip(1);
            final p2915 = _bits.read(15);
            _bits.skip(1);
            final p140 = _bits.read(15);
            _bits.skip(1);
            pts = (p3230 * 1073741824 + p2915 * 32768 + p140) / 90000;
          }
          final payloadLength = packetLength != 0
              ? packetLength - headerLength - 3
              : 0;
          pi
            ..totalLength = payloadLength
            ..currentLength = 0
            ..pts = pts;
        }
        _bits.index = payloadBeginIndex;
      }

      if (streamId != null) {
        final pi = _pes[streamId];
        if (pi != null) {
          final start = _bits.index >> 3;
          if (end > start) {
            pi.buffers.add(
              Uint8List.fromList(
                Uint8List.sublistView(_bits.bytes, start, end),
              ),
            );
            pi.currentLength += end - start;
          }
          final complete =
              pi.totalLength != 0 && pi.currentLength >= pi.totalLength;
          final hasPadding = !payloadStart && (adaptationField & 0x2) != 0;
          if (complete || (guessVideoFrameEnd && hasPadding)) _complete(pi);
        }
      }
    }
    _bits.index = end << 3;
    return true;
  }

  bool _resync() {
    if (!_bits.has((188 * 6) << 3)) return false;
    final byteIndex = _bits.index >> 3;
    for (var i = 0; i < 187; i++) {
      if (_bits.bytes[byteIndex + i] == 0x47) {
        var found = true;
        for (var j = 1; j < 5; j++) {
          final k = byteIndex + i + 188 * j;
          if (k >= _bits.byteLength || _bits.bytes[k] != 0x47) {
            found = false;
            break;
          }
        }
        if (found) {
          _bits.index = (byteIndex + i + 1) << 3;
          return true;
        }
      }
    }
    _bits.skip(187 << 3);
    return false;
  }

  void _complete(_PesPacket pi) {
    if (pi.buffers.isNotEmpty) pi.sink(pi.pts, pi.buffers);
    pi
      ..totalLength = 0
      ..currentLength = 0
      ..buffers = [];
  }
}
