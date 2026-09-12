import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }
  runApp(const SmartLensApp());
}

/// Root widget. Holds the current ThemeMode, which is flipped by
/// [CameraHomePage] based on ambient brightness measured from the
/// camera feed.
///
/// Logic (as requested): bright surroundings -> Dark UI theme.
///                        dark surroundings   -> Light/White UI theme.
class SmartLensApp extends StatefulWidget {
  const SmartLensApp({super.key});

  @override
  State<SmartLensApp> createState() => _SmartLensAppState();
}

class _SmartLensAppState extends State<SmartLensApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _updateTheme(bool isDarkEnvironment) {
    final target = isDarkEnvironment ? ThemeMode.light : ThemeMode.dark;
    if (target != _themeMode) {
      setState(() => _themeMode = target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Useless Lens',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: CameraHomePage(onEnvironmentChanged: _updateTheme),
    );
  }
}

class CameraHomePage extends StatefulWidget {
  final ValueChanged<bool> onEnvironmentChanged;
  const CameraHomePage({super.key, required this.onEnvironmentChanged});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isDark = false;
  bool _torchOn = false;
  bool _autoMode = true;
  bool _permissionGranted = false;
  DateTime _lastProcessed = DateTime.now();
  bool _busy = false;

  // Hysteresis thresholds (0-255 luminance) so the app doesn't flicker
  // back and forth right at the boundary.
  static const double _darkThreshold = 60;
  static const double _lightThreshold = 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (!status.isGranted || cameras.isEmpty) {
      setState(() => _permissionGranted = false);
      return;
    }
    setState(() => _permissionGranted = true);

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    setState(() {});
    await controller.startImageStream(_onFrame);
  }

  // Reads the Y (luma) plane of each camera frame to estimate ambient
  // brightness -- no extra sensor plugin needed.
  void _onFrame(CameraImage image) {
    if (_busy || !_autoMode) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < 500) return;
    _lastProcessed = now;
    _busy = true;

    try {
      final bytes = image.planes[0].bytes;
      int sum = 0;
      int count = 0;
      for (int i = 0; i < bytes.length; i += 20) {
        sum += bytes[i];
        count++;
      }
      final avgLuma = count > 0 ? sum / count : 128;

      bool newIsDark = _isDark;
      if (avgLuma < _darkThreshold) {
        newIsDark = true;
      } else if (avgLuma > _lightThreshold) {
        newIsDark = false;
      }

      if (newIsDark != _isDark) {
        _isDark = newIsDark;
        _applyEnvironment();
      }
    } catch (_) {
      // Ignore malformed frame.
    } finally {
      _busy = false;
    }
  }

  Future<void> _applyEnvironment() async {
    if (!mounted) return;
    setState(() {});
    widget.onEnvironmentChanged(_isDark);
    if (_autoMode) {
      await _setTorch(_isDark);
    }
  }

  Future<void> _setTorch(bool on) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = on);
    } catch (_) {}
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final wasStreaming = controller.value.isStreamingImages;
      if (wasStreaming) await controller.stopImageStream();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/smart_lens_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await controller.takePicture();
      await file.saveTo(path);
      if (wasStreaming) await controller.startImageStream(_onFrame);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: ${path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Camera permission is needed for Smart Lens to work.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _init,
                  child: const Text('Grant permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.35),
        elevation: 0,
        title: const Text('Useless Lens'),
        actions: [
          Row(
            children: [
              const Text('Auto', style: TextStyle(fontSize: 13)),
              Switch(
                value: _autoMode,
                onChanged: (v) => setState(() => _autoMode = v),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.45), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            top: 90,
            left: 16,
            right: 16,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isDark
                    ? Colors.white.withOpacity(0.9)
                    : Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _isDark ? Icons.nightlight_round : Icons.wb_sunny,
                    color: _isDark ? Colors.black87 : Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isDark
                          ? 'Dark surroundings · Light UI · Torch ${_torchOn ? "ON" : "off"}'
                          : 'Bright surroundings · Dark UI · Torch off',
                      style: TextStyle(
                        color: _isDark ? Colors.black87 : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: _torchOn
                        ? Colors.amber
                        : (_isDark ? Colors.black45 : Colors.white70),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (!_autoMode)
            Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  heroTag: 'torchBtn',
                  backgroundColor:
                      _torchOn ? Colors.amber : Colors.grey.shade800,
                  onPressed: () => _setTorch(!_torchOn),
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                  label: Text(_torchOn ? 'Torch on' : 'Torch off'),
                ),
              ),
            ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _capturePhoto,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white24,
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 32),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
