import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:valrove/features/camera/mpeg/mpeg1_decoder.dart';
import 'package:valrove/features/camera/mpeg/ts_demuxer.dart';

/// Decodes the ffmpeg-generated MPEG-TS/MPEG-1 fixture (I- and P-frames,
/// GOP of 6) and compares every frame's luma with ffmpeg's own decode.
void main() {
  test('MPEG-1 port matches ffmpeg (luma PSNR)', () {
    final ts = File('test/fixtures/camera/stream.ts').readAsBytesSync();
    final reference = File('test/fixtures/camera/luma.y').readAsBytesSync();
    const w = 176, h = 144;

    final decoder = Mpeg1Decoder();
    final demuxer = TsDemuxer();
    final frames = <Uint8List>[];
    demuxer.connect(TsDemuxer.videoStream, (pts, buffers) {
      decoder.write(buffers);
      while (decoder.decode()) {
        frames.add(decoder.lumaPlane()!);
      }
    });

    // Feed in odd-sized chunks to exercise packet reassembly.
    var offset = 0;
    final random = math.Random(42);
    while (offset < ts.length) {
      final n = math.min(ts.length - offset, 200 + random.nextInt(1800));
      demuxer.write(Uint8List.sublistView(ts, offset, offset + n));
      offset += n;
    }

    expect(decoder.width, w);
    expect(decoder.height, h);
    final expectedFrames = reference.length ~/ (w * h);
    // The last frame is flushed only when the next PES starts; allow it to
    // be pending at end of stream.
    expect(frames.length, greaterThanOrEqualTo(expectedFrames - 1));

    for (var i = 0; i < frames.length; i++) {
      final ref = Uint8List.sublistView(reference, i * w * h, (i + 1) * w * h);
      var mse = 0.0;
      for (var p = 0; p < w * h; p++) {
        final d = frames[i][p] - ref[p];
        mse += d * d;
      }
      mse /= w * h;
      final psnr = mse == 0 ? 99.0 : 10 * math.log(255 * 255 / mse) / math.ln10;
      expect(psnr, greaterThan(48), reason: 'frame $i PSNR $psnr dB');
    }

    final rgba = decoder.toRgba()!;
    expect(rgba.length, w * h * 4);
    expect(rgba[3], 255);
  });
}
