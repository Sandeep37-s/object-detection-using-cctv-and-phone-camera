import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'detector.dart';
import 'overlay.dart';
import 'settings.dart';

/// Live detection using the phone's own camera.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.detector, required this.settings});

  final Detector detector;
  final AppSettings settings;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription> _cameras = [];
  int _camIndex = 0;
  CameraController? _controller;
  String? _error;

  List<Detection> _dets = const [];
  int _ms = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('No camera found on this device');
      await _start(_cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back).clamp(0, 99));
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _start(int index) async {
    final old = _controller;
    setState(() {
      _controller = null;
      _dets = const [];
    });
    await old?.dispose();

    _camIndex = index;
    final c = CameraController(
      _cameras[index],
      ResolutionPreset.medium, // 640x480 is plenty for a 640 model
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await c.initialize();
      await c.startImageStream(_onFrame);
      if (!mounted) return c.dispose();
      setState(() => _controller = c);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Camera permission denied. Allow it in Android Settings → Apps.'
          : '${e.code}: ${e.description}');
    }
  }

  void _onFrame(CameraImage img) {
    if (widget.detector.busy || img.planes.length < 3) return; // drop frame
    final cam = _cameras[_camIndex];
    widget.detector
        .detectYuv(
          width: img.width,
          height: img.height,
          y: img.planes[0].bytes,
          u: img.planes[1].bytes,
          v: img.planes[2].bytes,
          yRowStride: img.planes[0].bytesPerRow,
          uvRowStride: img.planes[1].bytesPerRow,
          uvPixelStride: img.planes[1].bytesPerPixel ?? 1,
          rotation: cam.sensorOrientation,
        )
        .then((r) {
      if (!mounted) return;
      final s = widget.settings, allowed = s.classes, conf = s.confidence;
      setState(() {
        _dets = r.detections.where((d) => d.score >= conf && allowed.contains(d.cls)).toList();
        _ms = r.inferenceMs;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final front = _cameras.isNotEmpty && _cameras[_camIndex].lensDirection == CameraLensDirection.front;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Phone camera'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              tooltip: 'Switch camera',
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: () => _start((_camIndex + 1) % _cameras.length),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
                : c == null || !c.value.isInitialized
                    ? const CircularProgressIndicator()
                    // Portrait: preview is upright, so aspect = height / width.
                    : AspectRatio(
                        aspectRatio: 1 / c.value.aspectRatio,
                        child: Stack(fit: StackFit.expand, children: [
                          CameraPreview(c),
                          CustomPaint(painter: DetectionPainter(_dets, mirror: front)),
                        ]),
                      ),
          ),
        ),
        StatsBar(detections: _dets, ms: _ms),
      ]),
    );
  }
}
