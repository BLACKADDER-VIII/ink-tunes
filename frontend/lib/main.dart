import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String _backendHost = 'http://localhost:7000';

void main() => runApp(const InkTunesApp());

class InkTunesApp extends StatelessWidget {
  const InkTunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5E60CE),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Ink Tunes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

enum BackendStatus { stopped, starting, running, stopping, failed }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BackendStatus _status = BackendStatus.stopped;
  Process? _backend;
  String? _backendDir;
  PlatformFile? _picked;
  String? _statusMessage;
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _backendDir = _detectBackendDir();
  }

  @override
  void dispose() {
    _backend?.kill(ProcessSignal.sigterm);
    super.dispose();
  }

  String? _detectBackendDir() {
    // Search both cwd (works under `flutter run`) and the resolved executable
    // directory (works when launching the .app bundle, where cwd is `/`).
    final roots = <String>{
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    };
    for (final root in roots) {
      final hit = _walkUpForBackend(Directory(root));
      if (hit != null) return hit;
    }
    return null;
  }

  String? _walkUpForBackend(Directory start) {
    final wrapper = Platform.isWindows ? 'gradlew.bat' : 'gradlew';
    Directory d = start;
    for (int i = 0; i < 15; i++) {
      final candidate = Directory(p.join(d.path, 'audiveris_backend'));
      if (candidate.existsSync() &&
          File(p.join(candidate.path, wrapper)).existsSync()) {
        return candidate.path;
      }
      final parent = d.parent;
      if (parent.path == d.path) break;
      d = parent;
    }
    return null;
  }

  Future<void> _startBackend() async {
    if (_backendDir == null) {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Locate audiveris_backend folder',
      );
      if (dir == null) return;
      setState(() => _backendDir = dir);
    }

    setState(() {
      _status = BackendStatus.starting;
      _statusMessage = 'Launching Audiveris backend (this can take a minute)…';
    });

    try {
      final exec = Platform.isWindows ? 'gradlew.bat' : './gradlew';
      _backend = await Process.start(
        exec,
        ['-q', ':api:run'],
        workingDirectory: _backendDir,
        runInShell: true,
      );

      _backend!.stdout
          .transform(utf8.decoder)
          .listen((line) => debugPrint('[backend] $line'));
      _backend!.stderr
          .transform(utf8.decoder)
          .listen((line) => debugPrint('[backend!] $line'));

      unawaited(_backend!.exitCode.then((code) {
        if (!mounted) return;
        setState(() {
          _backend = null;
          if (_status != BackendStatus.stopping) {
            _status = BackendStatus.failed;
            _statusMessage = 'Backend exited unexpectedly (code $code)';
          } else {
            _status = BackendStatus.stopped;
            _statusMessage = 'Backend stopped';
          }
        });
      }));

      final ok = await _waitForHealth(timeout: const Duration(seconds: 180));
      if (!mounted) return;
      setState(() {
        if (ok) {
          _status = BackendStatus.running;
          _statusMessage = 'Backend ready on $_backendHost';
        } else {
          _status = BackendStatus.failed;
          _statusMessage = 'Backend did not respond on $_backendHost';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = BackendStatus.failed;
        _statusMessage = 'Failed to launch: $e';
      });
    }
  }

  Future<bool> _waitForHealth({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final r = await http
            .get(Uri.parse('$_backendHost/health'))
            .timeout(const Duration(seconds: 2));
        if (r.statusCode == 200) return true;
      } catch (_) {/* not up yet */}
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return false;
  }

  Future<void> _stopBackend() async {
    final proc = _backend;
    if (proc == null) return;
    setState(() {
      _status = BackendStatus.stopping;
      _statusMessage = 'Stopping backend…';
    });
    proc.kill(ProcessSignal.sigint);
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_backend != null) proc.kill(ProcessSignal.sigkill);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _picked = result.files.single);
    }
  }

  Future<void> _convert() async {
    final picked = _picked;
    if (picked == null || picked.path == null) return;

    setState(() {
      _converting = true;
      _statusMessage = 'Uploading and transcribing…';
    });

    try {
      final req =
          http.MultipartRequest('POST', Uri.parse('$_backendHost/transcribe'));
      req.files.add(await http.MultipartFile.fromPath('file', picked.path!));
      final streamed = await req.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _statusMessage =
              'Server error ${response.statusCode}: ${response.body}';
        });
        return;
      }

      final disp = response.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disp);
      final outName = match?.group(1) ??
          '${p.basenameWithoutExtension(picked.name)}.mxl';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save MusicXML',
        fileName: outName,
      );
      if (savePath == null) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Save cancelled');
        return;
      }
      await File(savePath).writeAsBytes(response.bodyBytes);
      if (!mounted) return;
      setState(() => _statusMessage = 'Saved to $savePath');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Conversion failed: $e');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canConvert = _status == BackendStatus.running &&
        _picked != null &&
        !_converting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ink Tunes'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _statusChip()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(_status == BackendStatus.running
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded),
                  label: Text(_startButtonLabel()),
                  onPressed: _onStartPressed(),
                ),
                const SizedBox(height: 28),
                _UploadDropZone(
                  picked: _picked,
                  onTap: _pickFile,
                  onClear: () => setState(() => _picked = null),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _converting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.music_note_rounded),
                  label: Text(_converting ? 'Converting…' : 'Convert'),
                  onPressed: canConvert ? _convert : null,
                ),
                const SizedBox(height: 24),
                if (_statusMessage != null)
                  Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 8),
                _backendPathRow(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backendPathRow(ColorScheme cs) {
    if (_backendDir == null) {
      return TextButton.icon(
        icon: const Icon(Icons.folder_open, size: 16),
        label: const Text('Set backend folder'),
        onPressed: () async {
          final dir = await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Locate audiveris_backend folder',
          );
          if (dir != null) setState(() => _backendDir = dir);
        },
      );
    }
    return Text(
      'Backend: $_backendDir',
      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _startButtonLabel() => switch (_status) {
        BackendStatus.stopped => 'Start backend',
        BackendStatus.starting => 'Starting…',
        BackendStatus.running => 'Stop backend',
        BackendStatus.stopping => 'Stopping…',
        BackendStatus.failed => 'Retry start',
      };

  VoidCallback? _onStartPressed() {
    switch (_status) {
      case BackendStatus.stopped:
      case BackendStatus.failed:
        return _startBackend;
      case BackendStatus.running:
        return _stopBackend;
      case BackendStatus.starting:
      case BackendStatus.stopping:
        return null;
    }
  }

  Widget _statusChip() {
    final (Color color, String label) = switch (_status) {
      BackendStatus.stopped => (Colors.grey, 'Stopped'),
      BackendStatus.starting => (Colors.amber, 'Starting'),
      BackendStatus.running => (Colors.green, 'Running'),
      BackendStatus.stopping => (Colors.amber, 'Stopping'),
      BackendStatus.failed => (Colors.redAccent, 'Failed'),
    };
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _UploadDropZone extends StatelessWidget {
  final PlatformFile? picked;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _UploadDropZone({
    required this.picked,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: cs.outline,
            radius: 16,
            dash: 8,
            gap: 6,
            strokeWidth: 1.5,
          ),
          child: Container(
            height: 240,
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: picked == null
                ? _emptyState(context, cs)
                : _filledState(context, cs),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_upload_outlined, size: 56, color: cs.primary),
        const SizedBox(height: 12),
        Text('Click to upload',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('PDF or JPEG sheet music',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _filledState(BuildContext context, ColorScheme cs) {
    final sizeKb = (picked!.size / 1024).toStringAsFixed(1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.description_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 12),
        Text(
          picked!.name,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        const SizedBox(height: 4),
        Text('$sizeKb KB',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Remove'),
        ),
      ],
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}
