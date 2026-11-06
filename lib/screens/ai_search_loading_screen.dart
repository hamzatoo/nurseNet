import 'dart:async';
import 'package:flutter/material.dart';
import 'package:test1/theme.dart';
import 'package:test1/services/app_data_service.dart';

class AISearchLoadingScreen extends StatefulWidget {
  final String description;
  final List<String> tags;
  final bool needsResidentNurse;

  const AISearchLoadingScreen({
    super.key,
    required this.description,
    required this.tags,
    required this.needsResidentNurse,
  });

  @override
  State<AISearchLoadingScreen> createState() => _AISearchLoadingScreenState();
}

class _AISearchLoadingScreenState extends State<AISearchLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _currentStep = 0;
  bool _isSearchFinished = false;

  final List<String> _loadingSteps = [
    'جاري فحص وتدقيق حالتك الصحية المكتوبة...',
    'جاري تحليل الأوسمة وتصنيف نوع الرعاية المطلوبة...',
    'خوارزمية الذكاء الاصطناعي تبحث عن أقرب ممرض متاح...',
    'يتم الآن حساب وتصفية نسب التوافق...',
    'تم العثور على أفضل ممرضين متطابقين مع حالتك!',
  ];

  late Timer _stepTimer;
  late Timer _finishTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _stepTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_currentStep < _loadingSteps.length - 1) {
        setState(() => _currentStep++);
      } else {
        _stepTimer.cancel();
      }
    });

    _finishTimer = Timer(const Duration(seconds: 9), () {
      AppDataService.instance.findMatchingNurses(
        description: widget.description,
        tags: widget.tags,
        needsResidentNurse: widget.needsResidentNurse,
      );
      setState(() {
        _isSearchFinished = true;
        _animationController.stop();
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _stepTimer.cancel();
    _finishTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!_isSearchFinished)
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: RadarPainter(
                                _animationController.value,
                                AppColors.primary,
                              ),
                              child: Container(),
                            );
                          },
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isSearchFinished
                              ? Colors.green
                              : AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (_isSearchFinished
                                          ? Colors.green
                                          : AppColors.primary)
                                      .withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isSearchFinished
                              ? Icons.check_circle_outline
                              : Icons.psychology,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 50),
              Text(
                _isSearchFinished
                    ? 'اكتملت المطابقة بنجاح!'
                    : 'جاري مطابقة الذكاء الاصطناعي...',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 15),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  _loadingSteps[_currentStep],
                  key: ValueKey<int>(_currentStep),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: _isSearchFinished
                        ? Colors.green
                        : AppColors.textDark.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _isSearchFinished ? 1.0 : 0.0,
                child: _isSearchFinished
                    ? SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'عرض الممرضين المطابقين لك',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: 55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double animationValue;
  final Color color;

  RadarPainter(this.animationValue, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      double value = (animationValue + (i / 3)) % 1.0;
      double radius = maxRadius * value;
      paint.color = color.withOpacity((1.0 - value) * 0.5);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
