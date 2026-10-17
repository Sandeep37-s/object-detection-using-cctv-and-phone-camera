import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'camera_screen.dart';
import 'cctv_screen.dart';
import 'detector.dart';
import 'labels.dart';
import 'overlay.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = await AppSettings.load();
  runApp(YoloApp(settings: settings));
}

class YoloApp extends StatelessWidget {
  const YoloApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dhruva OD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(settings: settings),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Detector? _detector;
  String? _loadError;

  AppSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    Detector.create().then(
      (d) => setState(() => _detector = d),
      onError: (Object e) => setState(() => _loadError = '$e'),
    );
  }

  @override
  void dispose() {
    _detector?.dispose();
    super.dispose();
  }

  void _openCamera() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CameraScreen(detector: _detector!, settings: s)));
  }

  Future<void> _openCctv() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _CctvDialog(settings: s),
    );
    if (url == null || url.isEmpty || !mounted) return;
    s.addRecentUrl(url);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CctvScreen(detector: _detector!, settings: s, url: url)));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _detector != null;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dhruva OD',
                          style: theme.textTheme.headlineMedium!.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _loadError != null
                                    ? Colors.redAccent
                                    : ready
                                        ? const Color(0xFF10B981)
                                        : Colors.amberAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _loadError != null
                                    ? 'Model error: $_loadError'
                                    : ready
                                        ? 'Nano model loaded · runs 100% on device'
                                        : 'Loading model…',
                                style: TextStyle(
                                  color: _loadError != null ? Colors.redAccent : Colors.white60,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SourceCard(
                icon: Icons.photo_camera_outlined,
                title: 'Phone camera',
                subtitle: 'Use this phone or tablet\'s camera',
                enabled: ready,
                onTap: _openCamera,
              ),
              const SizedBox(height: 14),
              _SourceCard(
                icon: Icons.videocam_outlined,
                title: 'CCTV camera',
                subtitle: 'IP camera / DVR / NVR stream (RTSP or HTTP)',
                enabled: ready,
                onTap: _openCctv,
              ),
              const SizedBox(height: 32),
              Text('Settings', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Confidence threshold'),
                    subtitle: Slider(
                      value: s.confidence,
                      min: 0.1,
                      max: 0.9,
                      divisions: 16,
                      label: '${(s.confidence * 100).round()}%',
                      onChanged: (v) => s.confidence = v,
                    ),
                    trailing: Text('${(s.confidence * 100).round()}%'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text('Objects to detect'),
                    subtitle: Text('${s.classes.length} of 80 selected'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => ClassFilterScreen(settings: s))),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primary,
              child: Icon(icon, size: 30, color: scheme.onPrimary),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.75))),
              ]),
            ),
            enabled
                ? const Icon(Icons.arrow_forward_ios, size: 18)
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      ),
    );
  }
}

class _CctvDialog extends StatefulWidget {
  const _CctvDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_CctvDialog> createState() => _CctvDialogState();
}

class _CctvDialogState extends State<_CctvDialog> {
  late final _ctrl = TextEditingController(
      text: widget.settings.recentUrls.firstOrNull ?? 'rtsp://');

  @override
  Widget build(BuildContext context) {
    final recent = widget.settings.recentUrls;
    return AlertDialog(
      title: const Text('CCTV stream address'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'rtsp://user:pass@192.168.1.64:554/...',
            ),
          ),
          const SizedBox(height: 12),
          const Text('Examples (use the sub-stream for speed):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const SelectableText(
            'Hikvision: rtsp://admin:pass@IP:554/Streaming/Channels/102\n'
            'Dahua / CP Plus: rtsp://admin:pass@IP:554/cam/realmonitor?channel=1&subtype=1\n'
            'Phone "IP Webcam" app: http://IP:8080/video',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Recent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            for (final u in recent)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, u),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => widget.settings.removeRecentUrl(u)),
                ),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: const Text('Connect')),
      ],
    );
  }
}

/// Choose which of the 80 objects to show.
class ClassFilterScreen extends StatelessWidget {
  const ClassFilterScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final sel = settings.classes;
        return Scaffold(
          appBar: AppBar(
            title: Text('Objects (${sel.length}/80)'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => settings.classes = switch (v) {
                  'all' => {for (var i = 0; i < kLabels.length; i++) i},
                  'none' => {},
                  _ => {...kDefaultClasses},
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'all', child: Text('Select all')),
                  PopupMenuItem(value: 'none', child: Text('Clear all')),
                  PopupMenuItem(value: 'default', child: Text('Surveillance default')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final (name, first, last) in kCategories) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Row(children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        final ids = {for (var i = first; i <= last; i++) i};
                        settings.classes =
                            sel.containsAll(ids) ? sel.difference(ids) : sel.union(ids);
                      },
                      child: Text(sel.containsAll({for (var i = first; i <= last; i++) i}) ? 'None' : 'All'),
                    ),
                  ]),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = first; i <= last; i++)
                    FilterChip(
                      label: Text(kLabels[i]),
                      selected: sel.contains(i),
                      selectedColor: classColor(i).withValues(alpha: 0.35),
                      onSelected: (on) =>
                          settings.classes = on ? ({...sel, i}) : (sel.difference({i})),
                    ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}
