import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'heart_rate_capture_screen.dart';

/// Phase 1: explains how the contactless measurement works and how to prepare.
class HeartRateIntroScreen extends StatefulWidget {
  const HeartRateIntroScreen({super.key});

  @override
  State<HeartRateIntroScreen> createState() => _HeartRateIntroScreenState();
}

class _HeartRateIntroScreenState extends State<HeartRateIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  static const Color _deep = AppColors.background;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _startMeasurement() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HeartRateCaptureScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        _PulseOrb(animation: _pulse),
                        const SizedBox(height: 26),
                        const Text(
                          'قياس النبض بدون تلامس',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 26,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'كاميرا هاتفك تقرأ تدفّق الدم في جبهتك خلال 8 ثوانٍ فقط،\n'
                          'ثم يحوّل الذكاء الاصطناعي هذه الإشارة إلى نبضات في الدقيقة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textDark.withValues(alpha: 0.65),
                            fontSize: 13.5,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const _FeatureChips(),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            const Text(
                              'قبل أن نبدأ',
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.textDark.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const _TipCard(
                          index: '01',
                          icon: Icons.wb_sunny_outlined,
                          title: 'إضاءة قوية وطبيعية',
                          body:
                              'قف قرب نافذة نهارية أو في غرفة مضيئة. تجنّب الظلال '
                              'الحادة والإضاءة الخلفية القوية التي تجعل وجهك مظلماً.',
                          accent: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        const _TipCard(
                          index: '02',
                          icon: Icons.face_retouching_natural,
                          title: 'جبهتك داخل الدائرة',
                          body:
                              'املأ الإطار بوجهك وثبّت الجبهة في المنتصف طوال مدة '
                              'القياس. أزل القبعة والنظارات إن كانت تعكس الضوء.',
                          accent: AppColors.accent,
                        ),
                        const SizedBox(height: 12),
                        const _TipCard(
                          index: '03',
                          icon: Icons.self_improvement,
                          title: 'ثبات تام لمدة 8 ثوانٍ',
                          body:
                              'اجلس مستنداً على كرسي، تنفّس بهدوء، ولا تتحدث أثناء '
                              'القياس. أي حركة سريعة تُضعف دقة الإشارة.',
                          accent: const Color(0xFF7C6CF7),
                        ),
                        const SizedBox(height: 20),
                        _buildPrivacyNote(),
                      ],
                    ),
                  ),
                ),
                _buildStartButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          Text(
            'قياس حيوي ذكي',
            style: TextStyle(
              color: AppColors.textDark.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'خصوصيتك أولاً: يُرسل الفيديو للتحليل فقط ويُحذف من الخادم '
              'فور حساب النبض، ولا يُحفظ إلا الرقم الناتج عند موافقتك.',
              style: TextStyle(
                color: AppColors.textDark.withValues(alpha: 0.6),
                fontSize: 11.5,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _deep.withValues(alpha: 0),
            _deep,
            _deep,
          ],
        ),
      ),
      child: SizedBox(
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _startMeasurement,
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'ابدأ القياس',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: const [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    AppColors.background,
                    const Color(0xFFE8F0FE),
                  ],
                ),
              ),
            ),
          ),
          // Soft aurora glows keep the intro from feeling flat.
          Positioned(top: -120, right: -90, child: _Glow(size: 380, color: const Color(0x331A73E8))),
          Positioned(top: 300, left: -140, child: _Glow(size: 360, color: const Color(0x294285F4))),
          Positioned(bottom: -140, right: -60, child: _Glow(size: 400, color: const Color(0x221A73E8))),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _FeatureChips extends StatelessWidget {
  const _FeatureChips();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: const [
        _Chip(icon: Icons.timer_outlined, label: '8 ثوانٍ'),
        _Chip(icon: Icons.touch_app_outlined, label: 'بدون تلامس'),
        _Chip(icon: Icons.bolt_rounded, label: 'تحليل فوري'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textDark.withValues(alpha: 0.8),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String index;
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      index,
                      style: TextStyle(
                        color: AppColors.textDark.withValues(alpha: 0.25),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: AppColors.textDark.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.75,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.textDark, size: 18),
        ),
      ),
    );
  }
}

/// The animated heart surrounded by expanding pulse rings.
class _PulseOrb extends StatelessWidget {
  const _PulseOrb({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 208,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return CustomPaint(
            painter: _PulsePainter(progress: animation.value),
            child: Center(
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.accent, AppColors.primary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Transform.scale(
                  scale: 1 + 0.07 * math.sin(animation.value * math.pi * 2),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 58.0;

    for (var ring = 0; ring < 3; ring++) {
      final phase = (progress + ring / 3) % 1.0;
      final radius = baseRadius + phase * 62;
      final opacity = (1 - phase) * 0.4;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.accent.withValues(alpha: opacity),
      );
    }

    // A faint ECG trace under the orb hints at what the camera is reading.
    final path = Path();
    final width = size.width;
    final y = size.height - 26;
    for (var x = 0.0; x <= width; x += 3) {
      final t = x / width;
      final spike = math.exp(-math.pow((t - 0.5) * 42, 2).toDouble());
      final trough = math.exp(-math.pow((t - 0.5) * 14, 2).toDouble());
      path.lineTo(x, y + spike * 26 - trough * 4);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppColors.accent.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) => oldDelegate.progress != progress;
}
