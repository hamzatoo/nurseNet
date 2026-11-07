import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/heart_rate_reading.dart';
import '../../services/heart_rate_service.dart';
import '../../theme.dart';
import 'heart_rate_result_screen.dart';

enum _CapturePhase {
  initializing,
  ready,
  countdown,
  recording,
  analysing,
  error,
}

/// Phase 2: records an 8 second face clip, then hands it to the rPPG backend.
class HeartRateCaptureScreen extends StatefulWidget {
  const HeartRateCaptureScreen({super.key});

  @override
  State<HeartRateCaptureScreen> createState() => _HeartRateCaptureScreenState();
}

class _HeartRateCaptureScreenState extends State<HeartRateCaptureScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Long enough for the FFT to resolve frequencies, short enough to stay still.
  static const Duration _recordingDuration = Duration(seconds: 8);
  static const int _readyCountdown = 3;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];

  /// Cameras eligible for face capture - front-facing preferred, falls back to all.
  List<CameraDescription> _captureCameras = const [];
  int _cameraIndex = 0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _recordingDuration,
  );

  _CapturePhase _phase = _CapturePhase.initializing;
  int _countdown = _readyCountdown;
  bool _torchOn = false;
  String _errorMessage = '';
  String? _errorSuggestion;

  /// Incremented to cancel an in-flight sequence when the user leaves or retries.
  int _sequence = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    _sequence++;
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _sequence++;
      _progress.stop();
      if (_controller?.value.isRecordingVideo ?? false) {
        _controller?.stopVideoRecording().catchError((_) => XFile(''));
      }
      _controller?.dispose();
      _controller = null;
      if (mounted && _phase != _CapturePhase.error) {
        setState(() => _phase = _CapturePhase.initializing);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && mounted) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_disposed) return;
    setState(() {
      _phase = _CapturePhase.initializing;
      _errorMessage = '';
      _errorSuggestion = null;
    });

    try {
      _cameras = _cameras.isEmpty
          ? await availableCameras().timeout(const Duration(seconds: 10))
          : _cameras;
      if (_cameras.isEmpty) {
        _fail(
          'لا توجد كاميرا متاحة على هذا الجهاز.',
          'الميزة تتطلب كاميرا أمامية أو خلفية.',
        );
        return;
      }

      // Prefer the front camera - rPPG needs the user's face/forehead.
      final frontCameras = _cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .toList();
      _captureCameras = frontCameras.isNotEmpty ? frontCameras : _cameras;

      _cameraIndex %= _captureCameras.length;
      final camera = _captureCameras[_cameraIndex];
      final controller = CameraController(
        camera,
        // Medium resolution: enough forehead detail for rPPG, ~4x smaller
        // upload than high res, which keeps the request fast on mobile data.
        ResolutionPreset.medium,
        enableAudio: false,
        fps: 30,
      );

      await controller.initialize().timeout(const Duration(seconds: 15));
      if (_disposed) {
        await controller.dispose();
        return;
      }

      // Keep the preview sharp on the face: continuous focus where supported.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } on CameraException {
        // Older devices do not expose focus control; the default is fine.
      }

      await _controller?.dispose();
      _controller = controller;
      setState(() => _phase = _CapturePhase.ready);

      await _runSequence();
    } on CameraException catch (error) {
      debugPrint('Camera error: ${error.code} ${error.description}');
      _fail(
        error.code == 'CameraAccessDenied' || error.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'لم نستطع الوصول إلى الكاميرا.'
            : 'تعذّر تشغيل الكاميرا.',
        'امنح التطبيق صلاحية الكاميرا من إعدادات الجهاز، ثم أعد المحاولة.',
      );
    } catch (error) {
      debugPrint('Camera initialization failed: $error');
      _fail(
        'تعذّر تشغيل الكاميرا.',
        'أغلق التطبيقات الأخرى التي تستخدم الكاميرا ثم أعد المحاولة.',
      );
    }
  }

  void _fail(String message, [String? suggestion]) {
    if (!mounted) return;
    setState(() {
      _phase = _CapturePhase.error;
      _errorMessage = message;
      _errorSuggestion = suggestion;
    });
  }

  Future<void> _runSequence() async {
    final token = ++_sequence;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      setState(() {
        _phase = _CapturePhase.countdown;
        _countdown = _readyCountdown;
      });

      for (var remaining = _readyCountdown; remaining > 0; remaining--) {
        if (!mounted || token != _sequence) return;
        setState(() => _countdown = remaining);
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      if (!mounted || token != _sequence) return;

      await controller
          .startVideoRecording()
          .timeout(const Duration(seconds: 10));
      if (!mounted || token != _sequence) {
        await controller.stopVideoRecording();
        return;
      }

      setState(() => _phase = _CapturePhase.recording);
      _progress.forward(from: 0);

      await Future<void>.delayed(_recordingDuration);
      if (!mounted || token != _sequence) return;

      final clip = await controller
          .stopVideoRecording()
          .timeout(const Duration(seconds: 10));
      _progress.stop();
      if (!mounted || token != _sequence) return;

      setState(() => _phase = _CapturePhase.analysing);
      final clipFile = File(clip.path);
      HeartRateReading reading;
      try {
        reading = await HeartRateService.instance.measure(clipFile);
      } finally {
        // Free storage regardless of success/failure/cancellation.
        try {
          if (await clipFile.exists()) await clipFile.delete();
        } catch (_) {}
      }
      if (!mounted || token != _sequence) return;

      HapticFeedback.mediumImpact();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HeartRateResultScreen(reading: reading),
        ),
      );
    } on HeartRateException catch (error) {
      _fail(error.message, error.suggestion);
    } on CameraException catch (error) {
      debugPrint('Recording failed: ${error.code} ${error.description}');
      _fail('توقّف التسجيل قبل اكتماله.', 'أعد المحاولة وتأكد من عدم استخدام الكاميرا في تطبيق آخر.');
    } catch (error) {
      debugPrint('Measurement failed: $error');
      _fail('حدث خطأ أثناء القياس.', 'أعد المحاولة بعد قليل.');
    } finally {
      if (_progress.isAnimating) _progress.stop();
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(
        _torchOn ? FlashMode.off : FlashMode.torch,
      );
      setState(() => _torchOn = !_torchOn);
    } on CameraException {
      // Torch is optional: ignore on devices without one.
    }
  }

  Future<void> _switchCamera() async {
    if (_captureCameras.length < 2 || _phase == _CapturePhase.analysing) return;
    _sequence++;
    _progress.stop();
    _cameraIndex = (_cameraIndex + 1) % _captureCameras.length;
    _torchOn = false;
    await _initializeCamera();
  }

  /// Lets the user bail out while the backend is still analysing.
  /// The HTTP request finishes in the background; its result is ignored.
  Future<void> _cancelAnalysis() async {
    _sequence++;
    _progress.stop();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _cancel() async {
    _sequence++;
    _progress.stop();
    if (_controller?.value.isRecordingVideo ?? false) {
      try {
        await _controller?.stopVideoRecording();
      } catch (_) {
        // Nothing to clean up if the platform already stopped the recording.
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final previewReady =
        controller != null &&
        controller.value.isInitialized &&
        _phase != _CapturePhase.error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (previewReady) _buildPreview(controller),
          if (previewReady)
            AnimatedBuilder(
              animation: _progress,
              builder: (context, _) => CustomPaint(
                painter: _FaceGuidePainter(
                  scan: _progress.value,
                  active: _phase == _CapturePhase.recording,
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                if (_phase != _CapturePhase.error) _buildBottomPanel(),
              ],
            ),
          ),
          if (_phase == _CapturePhase.analysing) _buildAnalysingOverlay(),
          if (_phase == _CapturePhase.error) _buildErrorView(),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController controller) {
    final size = controller.value.previewSize;
    if (size == null) return const ColoredBox(color: Colors.black);
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _RoundButton(icon: Icons.close_rounded, onTap: _cancel),
          const Spacer(),
          if (_captureCameras.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _RoundButton(
                icon: Icons.cameraswitch_rounded,
                onTap: _phase == _CapturePhase.recording ? null : _switchCamera,
              ),
            ),
          _RoundButton(
            icon: _torchOn
                ? Icons.flashlight_on_rounded
                : Icons.flashlight_off_rounded,
            highlighted: _torchOn,
            onTap: _phase == _CapturePhase.recording ? null : _toggleTorch,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final recording = _phase == _CapturePhase.recording;
    final counting = _phase == _CapturePhase.countdown;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            recording
                ? 'ابقَ ثابتاً… الكاميرا تقرأ نبضك'
                : counting
                ? 'استعد، سيبدأ التسجيل'
                : _phase == _CapturePhase.ready
                ? 'ضع جبهتك داخل الدائرة'
                : 'جاري تجهيز الكاميرا…',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            recording
                ? 'لا تتحدث ولا تحرّك رأسك حتى ينتهي العدّ'
                : 'إضاءة جيدة على الوجه + مسافة 30–50 سم عن الكاميرا',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 104,
            height: 104,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                final progress = _progress.value;
                final secondsLeft = math.max(
                  0,
                  (_recordingDuration.inSeconds * (1 - progress)).ceil(),
                );
                return CustomPaint(
                  painter: _ProgressRingPainter(
                    progress: recording ? progress : 0,
                    counting: counting,
                  ),
                  child: Center(
                    child: counting
                        ? Text(
                            '$_countdown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : Text(
                            recording ? '$secondsLeft' : '8',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _cancel,
            child: Text(
              'إلغاء',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background.withValues(alpha: 0.95),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'جاري تحليل النبض…',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'نستخرج إشارة الدم من جبهتك، قد يستغرق ذلك حتى 20 ثانية.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textDark.withValues(alpha: 0.55),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                onPressed: _cancelAnalysis,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textDark.withValues(alpha: 0.6),
                ),
                label: Text(
                  'إلغاء والعودة',
                  style: TextStyle(
                    color: AppColors.textDark.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.videocam_off_rounded,
                    color: Color(0xFFEF4444),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                ),
                if (_errorSuggestion != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorSuggestion!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textDark.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      height: 1.8,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _initializeCamera,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'رجوع',
                    style: TextStyle(
                      color: AppColors.textDark.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final Future<void> Function()? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted
          ? const Color(0xFFFFC24B).withValues(alpha: 0.9)
          : Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null ? null : () => onTap!(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 20,
            color: highlighted ? const Color(0xFF2A1B00) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Darkens everything except the forehead oval and draws the scanning cue.
class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter({required this.scan, required this.active});

  final double scan;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final ovalWidth = math.min(size.width * 0.76, 320.0);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalWidth * 1.32,
    );

    // Dim everything outside the guide oval so the face is the only focal point.
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(ovalRect),
    );
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    // Re-draw a soft vignette inside the oval so the face stays readable.
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          AppColors.accent.withValues(alpha: 0.16),
        ],
        stops: const [0.6, 1],
      ).createShader(ovalRect);
    canvas.drawOval(ovalRect, glow);

    canvas.drawOval(
      ovalRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = (active ? AppColors.accent : Colors.white)
            .withValues(alpha: 0.85),
    );

    // Forehead band marker: the region the rPPG pipeline actually samples.
    final forehead = Rect.fromCenter(
      center: Offset(center.dx, ovalRect.top + ovalRect.height * 0.24),
      width: ovalWidth * 0.52,
      height: ovalWidth * 0.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(forehead, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.accent.withValues(alpha: active ? 0.9 : 0.4),
    );

    if (active) {
      final y = forehead.top + forehead.height * scan;
      final lineRect = Rect.fromLTWH(
        forehead.left,
        y - 1,
        forehead.width,
        2,
      );
      canvas.drawRect(
        lineRect,
        Paint()
          ..shader = LinearGradient(
            colors: [Colors.transparent, AppColors.accent, Colors.transparent],
          ).createShader(lineRect),
      );
    }

    // Corner brackets framing the capture area.
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.5);
    final guide = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: ovalWidth + 44,
      height: ovalRect.height + 44,
    );
    const arm = 24.0;
    for (final corner in [
      (guide.topLeft, 1, 1),
      (guide.topRight, -1, 1),
      (guide.bottomLeft, 1, -1),
      (guide.bottomRight, -1, -1),
    ]) {
      final (point, dx, dy) = corner;
      canvas.drawLine(point, point + Offset(arm * dx, 0), bracketPaint);
      canvas.drawLine(point, point + Offset(0, arm * dy), bracketPaint);
    }
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) =>
      oldDelegate.scan != scan || oldDelegate.active != active;
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress, required this.counting});

  final double progress;
  final bool counting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    final sweep = counting ? 1.0 : progress;
    if (sweep <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [AppColors.primary, AppColors.accent],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.counting != counting;
}
