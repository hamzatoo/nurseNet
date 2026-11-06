import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/heart_rate_reading.dart';
import '../../services/heart_rate_service.dart';
import '../../theme.dart';
import 'heart_rate_capture_screen.dart';

/// Phase 4: presents the estimated BPM and lets the patient save it.
class HeartRateResultScreen extends StatefulWidget {
  const HeartRateResultScreen({super.key, required this.reading});

  final HeartRateReading reading;

  @override
  State<HeartRateResultScreen> createState() => _HeartRateResultScreenState();
}

class _HeartRateResultScreenState extends State<HeartRateResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..forward();

  bool _saving = false;
  bool _saved = false;

  HeartRateReading get _reading => widget.reading;

  Color get _tone => switch (_reading.category) {
    HeartRateCategory.low => AppColors.accent,
    HeartRateCategory.normal => const Color(0xFF10B981),
    HeartRateCategory.elevated => const Color(0xFFF59E0B),
    HeartRateCategory.high => const Color(0xFFEF4444),
  };

  IconData get _icon => switch (_reading.category) {
    HeartRateCategory.low => Icons.trending_down_rounded,
    HeartRateCategory.normal => Icons.verified_rounded,
    HeartRateCategory.elevated => Icons.trending_up_rounded,
    HeartRateCategory.high => Icons.warning_amber_rounded,
  };

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      await HeartRateService.instance.saveReading(_reading);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ القياس في ملفك الطبي ✓'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on HeartRateException catch (error) {
      _showError(error.message, error.suggestion);
    } catch (error) {
      debugPrint('Saving heart rate failed: $error');
      _showError(
        'تعذّر حفظ القياس.',
        'تحقق من اتصالك بالإنترنت وصلاحيات الحساب.',
      );
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  void _showError(String message, String? suggestion) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          suggestion == null ? message : '$message\n$suggestion',
          style: const TextStyle(height: 1.5),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _measureAgain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HeartRateCaptureScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -160,
            left: -80,
            right: -80,
            child: Container(
              height: 360,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    _tone.withValues(alpha: 0.18),
                    _tone.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildGauge(),
                  const SizedBox(height: 18),
                  _buildStatusText(),
                  const SizedBox(height: 22),
                  _buildAdviceCard(),
                  const SizedBox(height: 14),
                  _buildDetailsCard(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _measureAgain,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('إعادة القياس'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textDark.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'هذا القياس تقديري عبر الكاميرا وليس بديلاً عن أجهزة القياس الطبية '
                    'المعتمدة. عند الشعور بأعراض غير طبيعية راجع مختصاً صحياً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10.5,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.close_rounded, size: 18, color: AppColors.textDark),
            ),
          ),
        ),
        const Spacer(),
        Text(
          'نتيجة القياس',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark.withValues(alpha: 0.55),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildGauge() {
    return SizedBox(
      height: 286,
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (context, _) {
          final value = Curves.easeOutCubic.transform(_reveal.value);
          final displayed = (_reading.bpm * value).round();
          return CustomPaint(
            painter: _BpmGaugePainter(
              progress: value,
              tone: _tone,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _tone.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon, size: 14, color: _tone),
                        const SizedBox(width: 6),
                        Text(
                          _reading.categoryLabel,
                          style: TextStyle(
                            color: _tone,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$displayed',
                    style: const TextStyle(
                      fontSize: 68,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'نبضة / دقيقة',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusText() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: _tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'نبضك ${_reading.categoryLabel}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _reading.qualityLabel,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildAdviceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined, color: _tone, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _reading.advice,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.8,
                color: AppColors.textDark.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final measuredAt = _reading.measuredAt;
    final time =
        '${measuredAt.hour.toString().padLeft(2, '0')}:'
        '${measuredAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _detailItem(
                Icons.timer_outlined,
                'مدة القياس',
                '${_reading.durationSeconds.toStringAsFixed(1)} ث',
              ),
              _detailItem(
                Icons.monitor_heart_outlined,
                'جودة الإشارة',
                '${_reading.qualityPercent.round()}%',
              ),
              _detailItem(Icons.schedule_rounded, 'الوقت', time),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _reading.qualityPercent / 100,
              minHeight: 7,
              backgroundColor: const Color(0xFFE8EEF7),
              valueColor: AlwaysStoppedAnimation(_tone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 17, color: AppColors.textDark.withValues(alpha: 0.4)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final saved = _saved;
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: saved
                ? const [Color(0xFF10B981), Color(0xFF34D399)]
                : [_tone, _tone.withValues(alpha: 0.82)],
          ),
          boxShadow: [
            BoxShadow(
              color: _tone.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _saving || saved ? null : _save,
            child: Center(
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          saved
                              ? Icons.check_circle_rounded
                              : Icons.cloud_upload_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          saved
                              ? 'تم الحفظ في ملفك الطبي'
                              : 'حفظ في الملف الطبي',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 270° gauge with a gradient sweep and a glowing tip.
class _BpmGaugePainter extends CustomPainter {
  _BpmGaugePainter({required this.progress, required this.tone});

  final double progress;
  final Color tone;

  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE6EDF7),
    );

    // Faint tick marks every 30° act as a medical scale.
    for (var i = 0; i <= 18; i++) {
      final angle = _startAngle + _sweepAngle * (i / 18);
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 22),
        center.dy + math.sin(angle) * (radius - 22),
      );
      final outer = Offset(
        center.dx + math.cos(angle) * (radius - 15),
        center.dy + math.sin(angle) * (radius - 15),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeWidth = 1.6
          ..color = const Color(0xFFD3DFEE),
      );
    }

    if (progress <= 0) return;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arcRect,
      _startAngle,
      _sweepAngle * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: [tone.withValues(alpha: 0.35), tone],
        ).createShader(arcRect),
    );

    final tipAngle = _startAngle + _sweepAngle * progress;
    final tip = Offset(
      center.dx + math.cos(tipAngle) * radius,
      center.dy + math.sin(tipAngle) * radius,
    );
    canvas.drawCircle(
      tip,
      9,
      Paint()..color = tone.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      tip,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      tip,
      3,
      Paint()..color = tone,
    );
  }

  @override
  bool shouldRepaint(_BpmGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tone != tone;
}
