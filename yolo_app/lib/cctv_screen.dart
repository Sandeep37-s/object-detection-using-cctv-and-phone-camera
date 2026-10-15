import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'detector.dart';
import 'overlay.dart';
import 'settings.dart';

/// Live detection on a CCTV / IP camera stream (RTSP or HTTP).
class CctvScreen extends StatefulWidget {
  const CctvScreen({super.key, required this.detector, required this.settings, required this.url});

  final Detector detector;
  final AppSettings settings;
  final String url;

  @override
  State<CctvScreen> createState() => _CctvScreenState();
}

class _CctvScreenState extends State<CctvScreen> {
  late final Player _player;
  late final VideoController _video;
  final _subs = <StreamSubscription>[];
  bool _running = true;

  int _w = 0, _h = 0;
  String? _status = 'Connecting…';
  List<Detection> _dets = const [];
  int _ms = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 4 * 1024 * 1024));
    // "mediacodec-copy" keeps decoded frames readable so we can run YOLO on them.
    _video = VideoController(_player,
        configuration: const VideoControllerConfiguration(hwdec: 'mediacodec-copy'));
    _open();
  }

  Future<void> _open() async {
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('rtsp-transport', 'tcp'); // more reliable over Wi-Fi
      await native.setProperty('profile', 'low-latency');
      await native.setProperty('network-timeout', '10');
    }
    _subs.add(_player.stream.width.listen((w) => setState(() => _w = w ?? 0)));
    _subs.add(_player.stream.height.listen((h) => setState(() => _h = h ?? 0)));
    _subs.add(_player.stream.error.listen((e) => setState(() => _status = 'Stream error: $e')));
    await _player.setVolume(0);
    await _player.open(Media(widget.url));
    _loop();
  }

  /// Grab the newest decoded frame, detect, repeat.
  Future<void> _loop() async {
    while (_running && mounted) {
      if (_w == 0 || _h == 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }
      try {
        final bytes = await _player.screenshot(format: null); // raw BGRA
        if (bytes == null || bytes.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final w = _w, h = _h;
        final r = await widget.detector.detectBgra(
            width: w, height: h, stride: bytes.length ~/ h, bytes: bytes);
        if (!mounted) return;
        final s = widget.settings, allowed = s.classes, conf = s.confidence;
        setState(() {
          _status = null;
          _dets = r.detections.where((d) => d.score >= conf && allowed.contains(d.cls)).toList();
          _ms = r.inferenceMs;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = 'Waiting for video… ($e)');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  void dispose() {
    _running = false;
    WakelockPlus.disable();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCTV camera'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
            child: Text(widget.url,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
          ),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: _w == 0 || _h == 0
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_status ?? '', textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    // Keep the video widget alive so frames decode.
                    const SizedBox(height: 1),
                    SizedBox(width: 1, height: 1, child: Video(controller: _video, controls: NoVideoControls)),
                  ])
                : AspectRatio(
                    aspectRatio: _w / _h,
                    child: Stack(fit: StackFit.expand, children: [
                      Video(controller: _video, controls: NoVideoControls, fit: BoxFit.fill),
                      CustomPaint(painter: DetectionPainter(_dets)),
                    ]),
                  ),
          ),
        ),
        StatsBar(detections: _dets, ms: _ms, status: _w == 0 ? _status : null),
      ]),
    );
  }
}
