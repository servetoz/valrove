// Port of jsmpeg's MPEG-1 video decoder (MIT License, (c) 2017 Dominic
// Szablewski), itself inspired by the Java MPEG-1 decoder by Zoltan Korandi.
//
// Decodes I- and P-pictures (B-pictures are skipped, as in jsmpeg) into
// YCbCr planes and converts them to RGBA.
import 'dart:typed_data';

import 'bit_buffer.dart';
import 'mpeg1_tables.dart' as t;

abstract final class _Start {
  static const sequence = 0xB3;
  static const sliceFirst = 0x01;
  static const sliceLast = 0xAF;
  static const picture = 0x00;
  static const extension = 0xB5;
  static const userData = 0xB2;
}

abstract final class _PictureType {
  static const intra = 1;
  static const predictive = 2;
  static const b = 3;
}

class Mpeg1Decoder {
  Mpeg1Decoder({int bufferSize = 512 * 1024})
    : _bits = BitBuffer(bufferSize, mode: BitBufferMode.evict);

  final BitBuffer _bits;
  final _customIntraQuantMatrix = Uint8List(64);
  final _customNonIntraQuantMatrix = Uint8List(64);
  final _blockData = Int32List(64);

  bool _hasSequenceHeader = false;
  int width = 0;
  int height = 0;
  double frameRate = 30;

  late Uint8List _intraQuantMatrix;
  late Uint8List _nonIntraQuantMatrix;
  int _mbWidth = 0;
  int _mbSize = 0;
  int _codedWidth = 0;
  int _codedHeight = 0;
  int _halfWidth = 0;

  late Uint8ClampedList _currentY, _currentCr, _currentCb;
  late Uint32List _currentY32, _currentCr32, _currentCb32;
  late Uint8ClampedList _forwardY, _forwardCr, _forwardCb;
  late Uint32List _forwardY32, _forwardCr32, _forwardCb32;

  int _pictureType = 0;
  bool _fullPelForward = false;
  int _forwardFCode = 0;
  int _forwardRSize = 0;
  int _forwardF = 0;

  int _quantizerScale = 0;
  bool _sliceBegin = false;
  int _macroblockAddress = 0;

  /// Last macroblock written in the current picture (for gap concealment).
  int _lastWritten = -1;
  int _mbRow = 0;
  int _mbCol = 0;
  int _macroblockType = 0;
  bool _macroblockIntra = false;
  bool _macroblockMotFw = false;
  int _motionFwH = 0, _motionFwV = 0, _motionFwHPrev = 0, _motionFwVPrev = 0;
  int _dcPredictorY = 0, _dcPredictorCr = 0, _dcPredictorCb = 0;

  int frames = 0;

  bool get hasSequenceHeader => _hasSequenceHeader;

  /// Feeds elementary stream data (PES payloads).
  void write(List<Uint8List> buffers) {
    _bits.write(buffers);
    if (!_hasSequenceHeader) {
      if (_bits.findStartCode(_Start.sequence) == -1) return;
      _decodeSequenceHeader();
    }
  }

  /// Decodes the next picture. Returns true if a picture was decoded and
  /// the planes now hold a displayable frame.
  bool decode() {
    if (!_hasSequenceHeader) return false;
    if (_bits.findStartCode(_Start.picture) == -1) return false;
    return _decodePicture();
  }

  int _readHuffman(List<int> codeTable) {
    var state = 0;
    do {
      state = codeTable[state + _bits.read(1)];
    } while (state >= 0 && codeTable[state] != 0);
    return codeTable[state + 2];
  }

  void _decodeSequenceHeader() {
    final newWidth = _bits.read(12);
    final newHeight = _bits.read(12);
    _bits.skip(4); // pixel aspect ratio
    const rates = [
      0.0,
      23.976,
      24.0,
      25.0,
      29.97,
      30.0,
      50.0,
      59.94,
      60.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
    ];
    final rate = rates[_bits.read(4)];
    if (rate > 0) frameRate = rate;
    _bits.skip(18 + 1 + 10 + 1); // bit rate, marker, buffer size, constrained

    if (newWidth != width || newHeight != height) {
      width = newWidth;
      height = newHeight;
      _initBuffers();
    }
    if (_bits.read(1) == 1) {
      for (var i = 0; i < 64; i++) {
        _customIntraQuantMatrix[t.zigZag[i]] = _bits.read(8);
      }
      _intraQuantMatrix = _customIntraQuantMatrix;
    }
    if (_bits.read(1) == 1) {
      for (var i = 0; i < 64; i++) {
        _customNonIntraQuantMatrix[t.zigZag[i]] = _bits.read(8);
      }
      _nonIntraQuantMatrix = _customNonIntraQuantMatrix;
    }
    _hasSequenceHeader = true;
  }

  void _initBuffers() {
    _intraQuantMatrix = t.defaultIntraQuantMatrix;
    _nonIntraQuantMatrix = t.defaultNonIntraQuantMatrix;
    _mbWidth = (width + 15) >> 4;
    final mbHeight = (height + 15) >> 4;
    _mbSize = _mbWidth * mbHeight;
    _codedWidth = _mbWidth << 4;
    final codedHeight = mbHeight << 4;
    _codedHeight = codedHeight;
    final codedSize = _codedWidth * codedHeight;
    _halfWidth = _mbWidth << 3;

    _currentY = Uint8ClampedList(codedSize);
    _currentY32 = _currentY.buffer.asUint32List();
    _currentCr = Uint8ClampedList(codedSize >> 2);
    _currentCr32 = _currentCr.buffer.asUint32List();
    _currentCb = Uint8ClampedList(codedSize >> 2);
    _currentCb32 = _currentCb.buffer.asUint32List();
    _forwardY = Uint8ClampedList(codedSize);
    _forwardY32 = _forwardY.buffer.asUint32List();
    _forwardCr = Uint8ClampedList(codedSize >> 2);
    _forwardCr32 = _forwardCr.buffer.asUint32List();
    _forwardCb = Uint8ClampedList(codedSize >> 2);
    _forwardCb32 = _forwardCb.buffer.asUint32List();
  }

  // Planes of the most recently decoded (displayable) picture.
  Uint8ClampedList? _lastY, _lastCb, _lastCr;

  bool _decodePicture() {
    _bits.skip(10); // temporal reference
    _pictureType = _bits.read(3);
    _bits.skip(16); // vbv delay

    if (_pictureType <= 0 || _pictureType >= _PictureType.b) return false;

    if (_pictureType == _PictureType.predictive) {
      _fullPelForward = _bits.read(1) == 1;
      _forwardFCode = _bits.read(3);
      if (_forwardFCode == 0) return false;
      _forwardRSize = _forwardFCode - 1;
      _forwardF = 1 << _forwardRSize;
    }

    var code = 0;
    do {
      code = _bits.findNextStartCode();
    } while (code == _Start.extension || code == _Start.userData);

    _lastWritten = -1;
    while (code >= _Start.sliceFirst && code <= _Start.sliceLast) {
      _decodeSlice(code & 0xFF);
      code = _bits.findNextStartCode();
    }
    if (code != -1) _bits.rewind(32);
    // Macroblocks not covered by any slice keep the reference content
    // (error concealment, like ffmpeg) instead of stale buffer data.
    _concealUpTo(_mbSize);

    _lastY = _currentY;
    _lastCb = _currentCb;
    _lastCr = _currentCr;
    frames++;

    // Rotate prediction buffers for reference pictures.
    final tY = _forwardY,
        tY32 = _forwardY32,
        tCr = _forwardCr,
        tCr32 = _forwardCr32,
        tCb = _forwardCb,
        tCb32 = _forwardCb32;
    _forwardY = _currentY;
    _forwardY32 = _currentY32;
    _forwardCr = _currentCr;
    _forwardCr32 = _currentCr32;
    _forwardCb = _currentCb;
    _forwardCb32 = _currentCb32;
    _currentY = tY;
    _currentY32 = tY32;
    _currentCr = tCr;
    _currentCr32 = tCr32;
    _currentCb = tCb;
    _currentCb32 = tCb32;
    return true;
  }

  void _decodeSlice(int slice) {
    _sliceBegin = true;
    _macroblockAddress = (slice - 1) * _mbWidth - 1;
    _motionFwH = _motionFwHPrev = 0;
    _motionFwV = _motionFwVPrev = 0;
    _dcPredictorY = 128;
    _dcPredictorCr = 128;
    _dcPredictorCb = 128;
    _quantizerScale = _bits.read(5);
    while (_bits.read(1) == 1) {
      _bits.skip(8);
    }
    do {
      _decodeMacroblock();
    } while (!_bits.nextBytesAreStartCode());
  }

  void _decodeMacroblock() {
    var increment = 0;
    var tt = _readHuffman(t.macroblockAddressIncrement);
    while (tt == 34) {
      tt = _readHuffman(t.macroblockAddressIncrement);
    }
    while (tt == 35) {
      increment += 33;
      tt = _readHuffman(t.macroblockAddressIncrement);
    }
    increment += tt;

    if (_sliceBegin) {
      _sliceBegin = false;
      _macroblockAddress += increment;
      _concealUpTo(_macroblockAddress);
    } else {
      if (_macroblockAddress + increment >= _mbSize) return;
      if (increment > 1) {
        _dcPredictorY = 128;
        _dcPredictorCr = 128;
        _dcPredictorCb = 128;
        if (_pictureType == _PictureType.predictive) {
          _motionFwH = _motionFwHPrev = 0;
          _motionFwV = _motionFwVPrev = 0;
        }
      }
      while (increment > 1) {
        _macroblockAddress++;
        _mbRow = _macroblockAddress ~/ _mbWidth;
        _mbCol = _macroblockAddress % _mbWidth;
        _copyMacroblock(
          _motionFwH,
          _motionFwV,
          _forwardY,
          _forwardCr,
          _forwardCb,
        );
        _lastWritten = _macroblockAddress;
        increment--;
      }
      _macroblockAddress++;
    }
    if (_macroblockAddress < 0 || _macroblockAddress >= _mbSize) return;
    _mbRow = _macroblockAddress ~/ _mbWidth;
    _mbCol = _macroblockAddress % _mbWidth;
    _lastWritten = _macroblockAddress;

    final table = _pictureType == _PictureType.intra
        ? t.macroblockTypeIntra
        : t.macroblockTypePredictive;
    _macroblockType = _readHuffman(table);
    _macroblockIntra = (_macroblockType & 0x01) != 0;
    _macroblockMotFw = (_macroblockType & 0x08) != 0;

    if ((_macroblockType & 0x10) != 0) _quantizerScale = _bits.read(5);

    if (_macroblockIntra) {
      _motionFwH = _motionFwHPrev = 0;
      _motionFwV = _motionFwVPrev = 0;
    } else {
      _dcPredictorY = 128;
      _dcPredictorCr = 128;
      _dcPredictorCb = 128;
      _decodeMotionVectors();
      _copyMacroblock(
        _motionFwH,
        _motionFwV,
        _forwardY,
        _forwardCr,
        _forwardCb,
      );
    }

    final cbp = (_macroblockType & 0x02) != 0
        ? _readHuffman(t.codeBlockPattern)
        : (_macroblockIntra ? 0x3f : 0);
    var mask = 0x20;
    for (var block = 0; block < 6; block++) {
      if ((cbp & mask) != 0) _decodeBlock(block);
      mask >>= 1;
    }
  }

  /// Copies macroblocks `_lastWritten + 1 … end - 1` from the reference
  /// picture (P-pictures only).
  void _concealUpTo(int end) {
    if (_pictureType != _PictureType.predictive) return;
    final row = _mbRow, col = _mbCol;
    for (var a = _lastWritten + 1; a < end && a < _mbSize; a++) {
      if (a < 0) continue;
      _mbRow = a ~/ _mbWidth;
      _mbCol = a % _mbWidth;
      _copyMacroblock(0, 0, _forwardY, _forwardCr, _forwardCb);
      _lastWritten = a;
    }
    _mbRow = row;
    _mbCol = col;
  }

  int _readMotionComponent() {
    final code = _readHuffman(t.motion);
    if (code != 0 && _forwardF != 1) {
      final r = _bits.read(_forwardRSize);
      var d = ((code.abs() - 1) << _forwardRSize) + r + 1;
      if (code < 0) d = -d;
      return d;
    }
    return code;
  }

  void _decodeMotionVectors() {
    if (_macroblockMotFw) {
      _motionFwHPrev += _readMotionComponent();
      if (_motionFwHPrev > (_forwardF << 4) - 1) {
        _motionFwHPrev -= _forwardF << 5;
      } else if (_motionFwHPrev < ((-_forwardF) << 4)) {
        _motionFwHPrev += _forwardF << 5;
      }
      _motionFwH = _motionFwHPrev;
      if (_fullPelForward) _motionFwH <<= 1;

      _motionFwVPrev += _readMotionComponent();
      if (_motionFwVPrev > (_forwardF << 4) - 1) {
        _motionFwVPrev -= _forwardF << 5;
      } else if (_motionFwVPrev < ((-_forwardF) << 4)) {
        _motionFwVPrev += _forwardF << 5;
      }
      _motionFwV = _motionFwVPrev;
      if (_fullPelForward) _motionFwV <<= 1;
    } else if (_pictureType == _PictureType.predictive) {
      _motionFwH = _motionFwHPrev = 0;
      _motionFwV = _motionFwVPrev = 0;
    }
  }

  /// JS `(x / 2) >> 1` semantics: truncate the half towards zero, then shift.
  static int _halfShift(int v) => (v / 2).truncate() >> 1;

  static bool _halfOdd(int v) => ((v / 2).truncate() & 1) == 1;

  void _copyMacroblock(
    int motionH,
    int motionV,
    Uint8ClampedList sY,
    Uint8ClampedList sCr,
    Uint8ClampedList sCb,
  ) {
    final dY = _currentY32, dCb = _currentCb32, dCr = _currentCr32;

    // Luminance
    var w = _codedWidth;
    var scan = w - 16;
    var h = motionH >> 1;
    var v = motionV >> 1;
    var oddH = (motionH & 1) == 1;
    var oddV = (motionV & 1) == 1;

    var src = ((_mbRow << 4) + v) * w + (_mbCol << 4) + h;
    var dest = (_mbRow * w + _mbCol) << 2;
    var last = dest + (w << 2);
    // References crossing the picture border use edge emulation (clamped
    // samples, as ffmpeg does) instead of the fast path.
    final lx = (_mbCol << 4) + h, ly = (_mbRow << 4) + v;
    if (lx < 0 ||
        ly < 0 ||
        lx + 16 + (oddH ? 1 : 0) > w ||
        ly + 16 + (oddV ? 1 : 0) > _codedHeight) {
      _copyClamped(
        sY,
        _currentY,
        w,
        _codedHeight,
        lx,
        ly,
        16,
        oddH,
        oddV,
        (_mbRow << 4) * w + (_mbCol << 4),
      );
      _copyChroma(motionH, motionV, sCr, sCb);
      return;
    }

    int y1, y2, y;
    if (oddH) {
      if (oddV) {
        while (dest < last) {
          y1 = sY[src] + sY[src + w];
          src++;
          for (var x = 0; x < 4; x++) {
            y2 = sY[src] + sY[src + w];
            src++;
            y = ((y1 + y2 + 2) >> 2) & 0xff;
            y1 = sY[src] + sY[src + w];
            src++;
            y |= ((y1 + y2 + 2) << 6) & 0xff00;
            y2 = sY[src] + sY[src + w];
            src++;
            y |= ((y1 + y2 + 2) << 14) & 0xff0000;
            y1 = sY[src] + sY[src + w];
            src++;
            y |= ((y1 + y2 + 2) << 22) & 0xff000000;
            dY[dest++] = y;
          }
          dest += scan >> 2;
          src += scan - 1;
        }
      } else {
        while (dest < last) {
          y1 = sY[src++];
          for (var x = 0; x < 4; x++) {
            y2 = sY[src++];
            y = ((y1 + y2 + 1) >> 1) & 0xff;
            y1 = sY[src++];
            y |= ((y1 + y2 + 1) << 7) & 0xff00;
            y2 = sY[src++];
            y |= ((y1 + y2 + 1) << 15) & 0xff0000;
            y1 = sY[src++];
            y |= ((y1 + y2 + 1) << 23) & 0xff000000;
            dY[dest++] = y;
          }
          dest += scan >> 2;
          src += scan - 1;
        }
      }
    } else {
      if (oddV) {
        while (dest < last) {
          for (var x = 0; x < 4; x++) {
            y = ((sY[src] + sY[src + w] + 1) >> 1) & 0xff;
            src++;
            y |= ((sY[src] + sY[src + w] + 1) << 7) & 0xff00;
            src++;
            y |= ((sY[src] + sY[src + w] + 1) << 15) & 0xff0000;
            src++;
            y |= ((sY[src] + sY[src + w] + 1) << 23) & 0xff000000;
            src++;
            dY[dest++] = y;
          }
          dest += scan >> 2;
          src += scan;
        }
      } else {
        while (dest < last) {
          for (var x = 0; x < 4; x++) {
            y = sY[src];
            src++;
            y |= sY[src] << 8;
            src++;
            y |= sY[src] << 16;
            src++;
            y |= sY[src] << 24;
            src++;
            dY[dest++] = y;
          }
          dest += scan >> 2;
          src += scan;
        }
      }
    }

    // Chrominance
    w = _halfWidth;
    scan = w - 8;
    h = _halfShift(motionH);
    v = _halfShift(motionV);
    oddH = _halfOdd(motionH);
    oddV = _halfOdd(motionV);

    src = ((_mbRow << 3) + v) * w + (_mbCol << 3) + h;
    dest = (_mbRow * w + _mbCol) << 1;
    last = dest + (w << 1);
    final cx = (_mbCol << 3) + h, cy = (_mbRow << 3) + v;
    if (cx < 0 ||
        cy < 0 ||
        cx + 8 + (oddH ? 1 : 0) > w ||
        cy + 8 + (oddV ? 1 : 0) > _codedHeight >> 1) {
      _copyChroma(motionH, motionV, sCr, sCb);
      return;
    }

    int cr1, cr2, cr, cb1, cb2, cb;
    if (oddH) {
      if (oddV) {
        while (dest < last) {
          cr1 = sCr[src] + sCr[src + w];
          cb1 = sCb[src] + sCb[src + w];
          src++;
          for (var x = 0; x < 2; x++) {
            cr2 = sCr[src] + sCr[src + w];
            cb2 = sCb[src] + sCb[src + w];
            src++;
            cr = ((cr1 + cr2 + 2) >> 2) & 0xff;
            cb = ((cb1 + cb2 + 2) >> 2) & 0xff;
            cr1 = sCr[src] + sCr[src + w];
            cb1 = sCb[src] + sCb[src + w];
            src++;
            cr |= ((cr1 + cr2 + 2) << 6) & 0xff00;
            cb |= ((cb1 + cb2 + 2) << 6) & 0xff00;
            cr2 = sCr[src] + sCr[src + w];
            cb2 = sCb[src] + sCb[src + w];
            src++;
            cr |= ((cr1 + cr2 + 2) << 14) & 0xff0000;
            cb |= ((cb1 + cb2 + 2) << 14) & 0xff0000;
            cr1 = sCr[src] + sCr[src + w];
            cb1 = sCb[src] + sCb[src + w];
            src++;
            cr |= ((cr1 + cr2 + 2) << 22) & 0xff000000;
            cb |= ((cb1 + cb2 + 2) << 22) & 0xff000000;
            dCr[dest] = cr;
            dCb[dest] = cb;
            dest++;
          }
          dest += scan >> 2;
          src += scan - 1;
        }
      } else {
        while (dest < last) {
          cr1 = sCr[src];
          cb1 = sCb[src];
          src++;
          for (var x = 0; x < 2; x++) {
            cr2 = sCr[src];
            cb2 = sCb[src++];
            cr = ((cr1 + cr2 + 1) >> 1) & 0xff;
            cb = ((cb1 + cb2 + 1) >> 1) & 0xff;
            cr1 = sCr[src];
            cb1 = sCb[src++];
            cr |= ((cr1 + cr2 + 1) << 7) & 0xff00;
            cb |= ((cb1 + cb2 + 1) << 7) & 0xff00;
            cr2 = sCr[src];
            cb2 = sCb[src++];
            cr |= ((cr1 + cr2 + 1) << 15) & 0xff0000;
            cb |= ((cb1 + cb2 + 1) << 15) & 0xff0000;
            cr1 = sCr[src];
            cb1 = sCb[src++];
            cr |= ((cr1 + cr2 + 1) << 23) & 0xff000000;
            cb |= ((cb1 + cb2 + 1) << 23) & 0xff000000;
            dCr[dest] = cr;
            dCb[dest] = cb;
            dest++;
          }
          dest += scan >> 2;
          src += scan - 1;
        }
      }
    } else {
      if (oddV) {
        while (dest < last) {
          for (var x = 0; x < 2; x++) {
            cr = ((sCr[src] + sCr[src + w] + 1) >> 1) & 0xff;
            cb = ((sCb[src] + sCb[src + w] + 1) >> 1) & 0xff;
            src++;
            cr |= ((sCr[src] + sCr[src + w] + 1) << 7) & 0xff00;
            cb |= ((sCb[src] + sCb[src + w] + 1) << 7) & 0xff00;
            src++;
            cr |= ((sCr[src] + sCr[src + w] + 1) << 15) & 0xff0000;
            cb |= ((sCb[src] + sCb[src + w] + 1) << 15) & 0xff0000;
            src++;
            cr |= ((sCr[src] + sCr[src + w] + 1) << 23) & 0xff000000;
            cb |= ((sCb[src] + sCb[src + w] + 1) << 23) & 0xff000000;
            src++;
            dCr[dest] = cr;
            dCb[dest] = cb;
            dest++;
          }
          dest += scan >> 2;
          src += scan;
        }
      } else {
        while (dest < last) {
          for (var x = 0; x < 2; x++) {
            cr = sCr[src];
            cb = sCb[src];
            src++;
            cr |= sCr[src] << 8;
            cb |= sCb[src] << 8;
            src++;
            cr |= sCr[src] << 16;
            cb |= sCb[src] << 16;
            src++;
            cr |= sCr[src] << 24;
            cb |= sCb[src] << 24;
            src++;
            dCr[dest] = cr;
            dCb[dest] = cb;
            dest++;
          }
          dest += scan >> 2;
          src += scan;
        }
      }
    }
  }

  /// Chroma motion compensation with edge emulation.
  void _copyChroma(
    int motionH,
    int motionV,
    Uint8ClampedList sCr,
    Uint8ClampedList sCb,
  ) {
    final w = _halfWidth;
    final hh = _codedHeight >> 1;
    final x = (_mbCol << 3) + _halfShift(motionH);
    final y = (_mbRow << 3) + _halfShift(motionV);
    final oddH = _halfOdd(motionH), oddV = _halfOdd(motionV);
    final dest = (_mbRow << 3) * w + (_mbCol << 3);
    _copyClamped(sCr, _currentCr, w, hh, x, y, 8, oddH, oddV, dest);
    _copyClamped(sCb, _currentCb, w, hh, x, y, 8, oddH, oddV, dest);
  }

  /// Copies a [size]² block from [src] at ([x], [y]) with half-pel
  /// interpolation, clamping samples to the picture (edge emulation).
  static void _copyClamped(
    Uint8ClampedList src,
    Uint8ClampedList dst,
    int w,
    int h,
    int x,
    int y,
    int size,
    bool oddH,
    bool oddV,
    int dest,
  ) {
    int s(int sx, int sy) =>
        src[(sy < 0 ? 0 : (sy >= h ? h - 1 : sy)) * w +
            (sx < 0 ? 0 : (sx >= w ? w - 1 : sx))];
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final px = x + col, py = y + row;
        int value;
        if (oddH && oddV) {
          value =
              (s(px, py) +
                  s(px + 1, py) +
                  s(px, py + 1) +
                  s(px + 1, py + 1) +
                  2) >>
              2;
        } else if (oddH) {
          value = (s(px, py) + s(px + 1, py) + 1) >> 1;
        } else if (oddV) {
          value = (s(px, py) + s(px, py + 1) + 1) >> 1;
        } else {
          value = s(px, py);
        }
        dst[dest + row * w + col] = value;
      }
    }
  }

  void _decodeBlock(int block) {
    var n = 0;
    Uint8List quantMatrix;

    if (_macroblockIntra) {
      int predictor;
      int dctSize;
      if (block < 4) {
        predictor = _dcPredictorY;
        dctSize = _readHuffman(t.dctDcSizeLuminance);
      } else {
        predictor = block == 4 ? _dcPredictorCr : _dcPredictorCb;
        dctSize = _readHuffman(t.dctDcSizeChrominance);
      }
      if (dctSize > 0) {
        final differential = _bits.read(dctSize);
        if ((differential & (1 << (dctSize - 1))) != 0) {
          _blockData[0] = predictor + differential;
        } else {
          _blockData[0] = predictor + ((-1 << dctSize) | (differential + 1));
        }
      } else {
        _blockData[0] = predictor;
      }
      if (block < 4) {
        _dcPredictorY = _blockData[0];
      } else if (block == 4) {
        _dcPredictorCr = _blockData[0];
      } else {
        _dcPredictorCb = _blockData[0];
      }
      _blockData[0] <<= 3 + 5;
      quantMatrix = _intraQuantMatrix;
      n = 1;
    } else {
      quantMatrix = _nonIntraQuantMatrix;
    }

    var level = 0;
    while (true) {
      var run = 0;
      final coeff = _readHuffman(t.dctCoeff);
      if (coeff == 0x0001 && n > 0 && _bits.read(1) == 0) break; // end of block
      if (coeff == 0xffff) {
        run = _bits.read(6);
        level = _bits.read(8);
        if (level == 0) {
          level = _bits.read(8);
        } else if (level == 128) {
          level = _bits.read(8) - 256;
        } else if (level > 128) {
          level = level - 256;
        }
      } else {
        run = coeff >> 8;
        level = coeff & 0xff;
        if (_bits.read(1) == 1) level = -level;
      }

      n += run;
      if (n > 63) break; // corrupt data
      final dezigZagged = t.zigZag[n];
      n++;

      level <<= 1;
      if (!_macroblockIntra) level += level < 0 ? -1 : 1;
      level = (level * _quantizerScale * quantMatrix[dezigZagged]) >> 4;
      if ((level & 1) == 0) level -= level > 0 ? 1 : -1;
      if (level > 2047) {
        level = 2047;
      } else if (level < -2048) {
        level = -2048;
      }
      _blockData[dezigZagged] = level * t.premultiplierMatrix[dezigZagged];
    }

    Uint8ClampedList destArray;
    int destIndex;
    int scan;
    if (block < 4) {
      destArray = _currentY;
      scan = _codedWidth - 8;
      destIndex = (_mbRow * _codedWidth + _mbCol) << 4;
      if ((block & 1) != 0) destIndex += 8;
      if ((block & 2) != 0) destIndex += _codedWidth << 3;
    } else {
      destArray = block == 4 ? _currentCb : _currentCr;
      scan = (_codedWidth >> 1) - 8;
      destIndex = ((_mbRow * _codedWidth) << 2) + (_mbCol << 3);
    }

    if (_macroblockIntra) {
      if (n == 1) {
        _copyValue((_blockData[0] + 128) >> 8, destArray, destIndex, scan);
        _blockData[0] = 0;
      } else {
        _idct(_blockData);
        _copyBlock(_blockData, destArray, destIndex, scan);
        _blockData.fillRange(0, 64, 0);
      }
    } else {
      if (n == 1) {
        _addValue((_blockData[0] + 128) >> 8, destArray, destIndex, scan);
        _blockData[0] = 0;
      } else {
        _idct(_blockData);
        _addBlock(_blockData, destArray, destIndex, scan);
        _blockData.fillRange(0, 64, 0);
      }
    }
  }

  static void _copyBlock(
    Int32List block,
    Uint8ClampedList dest,
    int index,
    int scan,
  ) {
    for (var n = 0; n < 64; n += 8, index += scan + 8) {
      for (var k = 0; k < 8; k++) {
        dest[index + k] = block[n + k];
      }
    }
  }

  static void _addBlock(
    Int32List block,
    Uint8ClampedList dest,
    int index,
    int scan,
  ) {
    for (var n = 0; n < 64; n += 8, index += scan + 8) {
      for (var k = 0; k < 8; k++) {
        dest[index + k] = dest[index + k] + block[n + k];
      }
    }
  }

  static void _copyValue(
    int value,
    Uint8ClampedList dest,
    int index,
    int scan,
  ) {
    for (var n = 0; n < 64; n += 8, index += scan + 8) {
      for (var k = 0; k < 8; k++) {
        dest[index + k] = value;
      }
    }
  }

  static void _addValue(int value, Uint8ClampedList dest, int index, int scan) {
    for (var n = 0; n < 64; n += 8, index += scan + 8) {
      for (var k = 0; k < 8; k++) {
        dest[index + k] = dest[index + k] + value;
      }
    }
  }

  static void _idct(Int32List block) {
    int b1,
        b3,
        b4,
        b6,
        b7,
        tmp1,
        tmp2,
        m0,
        x0,
        x1,
        x2,
        x3,
        x4,
        y3,
        y4,
        y5,
        y6,
        y7;
    for (var i = 0; i < 8; ++i) {
      b1 = block[4 * 8 + i];
      b3 = block[2 * 8 + i] + block[6 * 8 + i];
      b4 = block[5 * 8 + i] - block[3 * 8 + i];
      tmp1 = block[1 * 8 + i] + block[7 * 8 + i];
      tmp2 = block[3 * 8 + i] + block[5 * 8 + i];
      b6 = block[1 * 8 + i] - block[7 * 8 + i];
      b7 = tmp1 + tmp2;
      m0 = block[0 * 8 + i];
      x4 = ((b6 * 473 - b4 * 196 + 128) >> 8) - b7;
      x0 = x4 - (((tmp1 - tmp2) * 362 + 128) >> 8);
      x1 = m0 - b1;
      x2 = (((block[2 * 8 + i] - block[6 * 8 + i]) * 362 + 128) >> 8) - b3;
      x3 = m0 + b1;
      y3 = x1 + x2;
      y4 = x3 + b3;
      y5 = x1 - x2;
      y6 = x3 - b3;
      y7 = -x0 - ((b4 * 473 + b6 * 196 + 128) >> 8);
      block[0 * 8 + i] = b7 + y4;
      block[1 * 8 + i] = x4 + y3;
      block[2 * 8 + i] = y5 - x0;
      block[3 * 8 + i] = y6 - y7;
      block[4 * 8 + i] = y6 + y7;
      block[5 * 8 + i] = x0 + y5;
      block[6 * 8 + i] = y3 - x4;
      block[7 * 8 + i] = y4 - b7;
    }
    for (var i = 0; i < 64; i += 8) {
      b1 = block[4 + i];
      b3 = block[2 + i] + block[6 + i];
      b4 = block[5 + i] - block[3 + i];
      tmp1 = block[1 + i] + block[7 + i];
      tmp2 = block[3 + i] + block[5 + i];
      b6 = block[1 + i] - block[7 + i];
      b7 = tmp1 + tmp2;
      m0 = block[0 + i];
      x4 = ((b6 * 473 - b4 * 196 + 128) >> 8) - b7;
      x0 = x4 - (((tmp1 - tmp2) * 362 + 128) >> 8);
      x1 = m0 - b1;
      x2 = (((block[2 + i] - block[6 + i]) * 362 + 128) >> 8) - b3;
      x3 = m0 + b1;
      y3 = x1 + x2;
      y4 = x3 + b3;
      y5 = x1 - x2;
      y6 = x3 - b3;
      y7 = -x0 - ((b4 * 473 + b6 * 196 + 128) >> 8);
      block[0 + i] = (b7 + y4 + 128) >> 8;
      block[1 + i] = (x4 + y3 + 128) >> 8;
      block[2 + i] = (y5 - x0 + 128) >> 8;
      block[3 + i] = (y6 - y7 + 128) >> 8;
      block[4 + i] = (y6 + y7 + 128) >> 8;
      block[5 + i] = (x0 + y5 + 128) >> 8;
      block[6 + i] = (y3 - x4 + 128) >> 8;
      block[7 + i] = (y4 - b7 + 128) >> 8;
    }
  }

  /// Luma plane of the last decoded picture, cropped to the display size.
  Uint8List? lumaPlane() {
    final y = _lastY;
    if (y == null) return null;
    final out = Uint8List(width * height);
    for (var row = 0; row < height; row++) {
      out.setRange(row * width, row * width + width, y, row * _codedWidth);
    }
    return out;
  }

  /// Converts the last decoded picture to RGBA (BT.601, jsmpeg's math).
  /// Returns null when no picture has been decoded yet.
  Uint8List? toRgba([Uint8List? reuse]) {
    final y = _lastY, cb = _lastCb, cr = _lastCr;
    if (y == null || cb == null || cr == null) return null;
    final out = (reuse != null && reuse.length == width * height * 4)
        ? reuse
        : Uint8List(width * height * 4);
    final rgba = Uint8ClampedList.view(
      out.buffer,
      out.offsetInBytes,
      out.length,
    );
    final w = ((width + 15) >> 4) << 4;
    final w2 = w >> 1;
    var yIndex1 = 0;
    var yIndex2 = w;
    final yNext2Lines = w + (w - width);
    var cIndex = 0;
    final cNextLine = w2 - (width >> 1);
    var rgbaIndex1 = 0;
    var rgbaIndex2 = width * 4;
    final rgbaNext2Lines = width * 4;
    final cols = width >> 1, rows = height >> 1;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final vCr = cr[cIndex];
        final vCb = cb[cIndex];
        cIndex++;
        final r = (vCr + ((vCr * 103) >> 8)) - 179;
        final g = ((vCb * 88) >> 8) - 44 + ((vCr * 183) >> 8) - 91;
        final b = (vCb + ((vCb * 198) >> 8)) - 227;

        final y1 = y[yIndex1++];
        final y2 = y[yIndex1++];
        rgba[rgbaIndex1] = y1 + r;
        rgba[rgbaIndex1 + 1] = y1 - g;
        rgba[rgbaIndex1 + 2] = y1 + b;
        rgba[rgbaIndex1 + 3] = 255;
        rgba[rgbaIndex1 + 4] = y2 + r;
        rgba[rgbaIndex1 + 5] = y2 - g;
        rgba[rgbaIndex1 + 6] = y2 + b;
        rgba[rgbaIndex1 + 7] = 255;
        rgbaIndex1 += 8;

        final y3 = y[yIndex2++];
        final y4 = y[yIndex2++];
        rgba[rgbaIndex2] = y3 + r;
        rgba[rgbaIndex2 + 1] = y3 - g;
        rgba[rgbaIndex2 + 2] = y3 + b;
        rgba[rgbaIndex2 + 3] = 255;
        rgba[rgbaIndex2 + 4] = y4 + r;
        rgba[rgbaIndex2 + 5] = y4 - g;
        rgba[rgbaIndex2 + 6] = y4 + b;
        rgba[rgbaIndex2 + 7] = 255;
        rgbaIndex2 += 8;
      }
      yIndex1 += yNext2Lines;
      yIndex2 += yNext2Lines;
      rgbaIndex1 += rgbaNext2Lines;
      rgbaIndex2 += rgbaNext2Lines;
      cIndex += cNextLine;
    }
    return out;
  }
}
