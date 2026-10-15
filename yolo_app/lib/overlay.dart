import 'package:flutter/material.dart';

import 'detector.dart';
import 'labels.dart';

/// Stable, distinct colour per class.
Color classColor(int cls) =>
    HSVColor.fromAHSV(1, (cls * 47) % 360.0, 0.85, 0.95).toColor();

/// Draws boxes + labels over a video. Must be laid out at exactly the same
/// size and aspect ratio as the video it covers.
class DetectionPainter extends CustomPainter {
  DetectionPainter(this.detections, {this.mirror = false});

  final List<Detection> detections;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      var x1 = d.x1, x2 = d.x2;
      if (mirror) (x1, x2) = (1 - d.x2, 1 - d.x1);
      final rect = Rect.fromLTRB(
          x1 * size.width, d.y1 * size.height, x2 * size.width, d.y2 * size.height);
      final color = classColor(d.cls);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: ' ${kLabels[d.cls]} ${(d.score * 100).round()}% ',
          style: const TextStyle(
              color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = rect.top - tp.height < 0 ? rect.top : rect.top - tp.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, top, tp.width, tp.height), const Radius.circular(3)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(rect.left, top));
    }
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections || old.mirror != mirror;
}

/// Bottom bar: object counts and speed.
class StatsBar extends StatelessWidget {
  const StatsBar({super.key, required this.detections, required this.ms, this.status});

  final List<Detection> detections;
  final int ms;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final d in detections) {
      counts[d.cls] = (counts[d.cls] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.75),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.speed, size: 16, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(
              status ?? (ms > 0 ? '$ms ms per frame  ·  ${(1000 / ms).toStringAsFixed(1)} FPS' : 'Starting…'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
            const Spacer(),
            const Text('OFFLINE',
                style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            const Text('No selected objects in view',
                style: TextStyle(color: Colors.white70, fontSize: 14))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in sorted)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: classColor(e.key),
                    side: BorderSide.none,
                    label: Text('${kLabels[e.key]} × ${e.value}',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
