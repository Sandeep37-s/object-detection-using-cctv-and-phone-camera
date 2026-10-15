import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Model input size (pixels). The ONNX file was exported at 640x640.
const int kInputSize = 640;

/// One detected object. Coordinates are 0..1 fractions of the upright frame.
class Detection {
  const Detection(this.x1, this.y1, this.x2, this.y2, this.score, this.cls);
  final double x1, y1, x2, y2, score;
  final int cls;
}

class DetectionResult {
  const DetectionResult(this.detections, this.inferenceMs);
  final List<Detection> detections;
  final int inferenceMs;
}

/// Runs the YOLO nano model on a background isolate so the UI never freezes.
///
/// Only one frame is processed at a time; callers should drop new frames
/// while [busy] is true (always process the newest frame, never queue).
class Detector {
  Detector._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  Completer<DetectionResult>? _pending;

  bool get busy => _pending != null;

  static Future<Detector> create() async {
    final model = await rootBundle.load('assets/yolo26n.onnx');
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, fromWorker.sendPort);
    final events = fromWorker.asBroadcastStream();
    final toWorker = await events.first as SendPort;
    toWorker.send({
      'op': 'init',
      'model': TransferableTypedData.fromList([model.buffer.asUint8List()]),
      'threads': math.max(2, math.min(4, Platform.numberOfProcessors)),
    });
    final ready = await events.first as Map;
    if (ready['op'] != 'ready') throw Exception('Model load failed: ${ready['msg']}');

    final d = Detector._(isolate, toWorker, fromWorker);
    events.listen(d._onMessage);
    return d;
  }

  void _onMessage(dynamic msg) {
    final m = msg as Map;
    final c = _pending;
    _pending = null;
    if (c == null) return;
    if (m['op'] == 'error') {
      c.completeError(Exception(m['msg']));
      return;
    }
    final raw = m['dets'] as Float32List;
    final dets = <Detection>[
      for (var i = 0; i < raw.length; i += 6)
        Detection(raw[i], raw[i + 1], raw[i + 2], raw[i + 3], raw[i + 4], raw[i + 5].toInt()),
    ];
    c.complete(DetectionResult(dets, m['ms'] as int));
  }

  Future<DetectionResult> _run(Map<String, Object> msg) {
    final c = _pending = Completer<DetectionResult>();
    _toWorker.send(msg);
    return c.future;
  }

  /// Phone camera frame (Android YUV420). [rotation] is the camera sensor
  /// orientation in degrees, used to turn the frame upright.
  Future<DetectionResult> detectYuv({
    required int width,
    required int height,
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotation,
  }) =>
      _run({
        'op': 'yuv',
        'w': width, 'h': height,
        'y': TransferableTypedData.fromList([y]),
        'u': TransferableTypedData.fromList([u]),
        'v': TransferableTypedData.fromList([v]),
        'yRow': yRowStride, 'uvRow': uvRowStride, 'uvPix': uvPixelStride,
        'rot': rotation,
      });

  /// CCTV stream frame (raw BGRA from the video player).
  Future<DetectionResult> detectBgra({
    required int width,
    required int height,
    required int stride,
    required Uint8List bytes,
  }) =>
      _run({
        'op': 'bgra',
        'w': width, 'h': height, 'stride': stride,
        'bytes': TransferableTypedData.fromList([bytes]),
      });

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _fromWorker.close();
  }
}

// ---------------------------------------------------------------------------
// Background isolate
// ---------------------------------------------------------------------------

void _workerMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);

  late OrtSession session;
  final runOptions = OrtRunOptions();
  final input = Float32List(3 * kInputSize * kInputSize);

  inbox.listen((msg) {
    final m = msg as Map;
    try {
      if (m['op'] == 'init') {
        OrtEnv.instance.init();
        final options = OrtSessionOptions()
          ..setIntraOpNumThreads(m['threads'] as int)
          ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
        final bytes = (m['model'] as TransferableTypedData).materialize().asUint8List();
        session = OrtSession.fromBuffer(bytes, options);
        out.send({'op': 'ready'});
        return;
      }

      final sw = Stopwatch()..start();
      final _Letterbox lb;
      if (m['op'] == 'yuv') {
        lb = _fillFromYuv(input, m);
      } else {
        lb = _fillFromBgra(input, m);
      }

      final tensor = OrtValueTensor.createTensorWithDataList(
          input, [1, 3, kInputSize, kInputSize]);
      final outputs = session.run(runOptions, {'images': tensor});
      tensor.release();
      // Output shape [1, 300, 6]: x1, y1, x2, y2 (input pixels), score, class.
      final rows = (outputs[0]!.value as List)[0] as List;
      for (final o in outputs) {
        o?.release();
      }

      final dets = <double>[];
      for (final r in rows) {
        final row = r as List;
        final score = (row[4] as num).toDouble();
        if (score < 0.10) continue;
        dets.addAll([
          (((row[0] as num) - lb.padX) / lb.scale / lb.w).clamp(0.0, 1.0),
          (((row[1] as num) - lb.padY) / lb.scale / lb.h).clamp(0.0, 1.0),
          (((row[2] as num) - lb.padX) / lb.scale / lb.w).clamp(0.0, 1.0),
          (((row[3] as num) - lb.padY) / lb.scale / lb.h).clamp(0.0, 1.0),
          score,
          (row[5] as num).toDouble(),
        ]);
      }
      out.send({'op': 'result', 'dets': Float32List.fromList(dets), 'ms': sw.elapsedMilliseconds});
    } catch (e) {
      out.send({'op': 'error', 'msg': '$e'});
    }
  });
}

/// How the upright frame was scaled and padded into the 640x640 input.
class _Letterbox {
  const _Letterbox(this.w, this.h, this.scale, this.padX, this.padY);
  final int w, h; // upright frame size
  final double scale;
  final int padX, padY;
}

_Letterbox _letterbox(int w, int h) {
  final scale = kInputSize / math.max(w, h);
  final nw = (w * scale).round(), nh = (h * scale).round();
  return _Letterbox(w, h, scale, (kInputSize - nw) ~/ 2, (kInputSize - nh) ~/ 2);
}

const double _padValue = 114 / 255;
const int _plane = kInputSize * kInputSize;

/// Writes one RGB pixel (0..255) into the CHW float tensor.
@pragma('vm:prefer-inline')
void _put(Float32List t, int idx, int r, int g, int b) {
  t[idx] = r / 255;
  t[_plane + idx] = g / 255;
  t[2 * _plane + idx] = b / 255;
}

_Letterbox _fillFromYuv(Float32List t, Map m) {
  final sw = m['w'] as int, sh = m['h'] as int, rot = m['rot'] as int;
  final y = (m['y'] as TransferableTypedData).materialize().asUint8List();
  final u = (m['u'] as TransferableTypedData).materialize().asUint8List();
  final v = (m['v'] as TransferableTypedData).materialize().asUint8List();
  final yRow = m['yRow'] as int, uvRow = m['uvRow'] as int, uvPix = m['uvPix'] as int;

  final upright = rot == 90 || rot == 270;
  final uw = upright ? sh : sw, uh = upright ? sw : sh;
  final lb = _letterbox(uw, uh);
  t.fillRange(0, t.length, _padValue);

  final nw = kInputSize - 2 * lb.padX, nh = kInputSize - 2 * lb.padY;
  final inv = 1 / lb.scale;
  for (var oy = 0; oy < nh; oy++) {
    final uy = math.min(uh - 1, (oy * inv).toInt());
    final rowBase = (oy + lb.padY) * kInputSize + lb.padX;
    for (var ox = 0; ox < nw; ox++) {
      final ux = math.min(uw - 1, (ox * inv).toInt());
      // Map upright pixel back to the sensor's pixel.
      int sx, sy;
      switch (rot) {
        case 90:
          sx = uy;
          sy = sh - 1 - ux;
        case 180:
          sx = sw - 1 - ux;
          sy = sh - 1 - uy;
        case 270:
          sx = sw - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }
      final yy = y[sy * yRow + sx];
      final uvi = (sy >> 1) * uvRow + (sx >> 1) * uvPix;
      final uu = u[uvi] - 128, vv = v[uvi] - 128;
      final r = (yy + 1.402 * vv).round().clamp(0, 255);
      final g = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
      final b = (yy + 1.772 * uu).round().clamp(0, 255);
      _put(t, rowBase + ox, r, g, b);
    }
  }
  return lb;
}

_Letterbox _fillFromBgra(Float32List t, Map m) {
  final w = m['w'] as int, h = m['h'] as int, stride = m['stride'] as int;
  final px = (m['bytes'] as TransferableTypedData).materialize().asUint8List();
  final lb = _letterbox(w, h);
  t.fillRange(0, t.length, _padValue);

  final nw = kInputSize - 2 * lb.padX, nh = kInputSize - 2 * lb.padY;
  final inv = 1 / lb.scale;
  for (var oy = 0; oy < nh; oy++) {
    final sy = math.min(h - 1, (oy * inv).toInt());
    final rowBase = (oy + lb.padY) * kInputSize + lb.padX;
    for (var ox = 0; ox < nw; ox++) {
      final i = sy * stride + math.min(w - 1, (ox * inv).toInt()) * 4;
      _put(t, rowBase + ox, px[i + 2], px[i + 1], px[i]);
    }
  }
  return lb;
}
