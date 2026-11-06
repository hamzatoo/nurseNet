import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import '../services/ocr_service.dart';
import 'add_medication_screen.dart';

/// Daily medication tracker rendered as a vertical timeline of time slots.
class MedicalKitScreen extends StatefulWidget {
  const MedicalKitScreen({super.key});

  @override
  State<MedicalKitScreen> createState() => _MedicalKitScreenState();
}

class _MedicalKitScreenState extends State<MedicalKitScreen> {
  final MedicationService _medicationService = MedicationService();
  final OCRService _ocrService = OCRService();

  late Stream<List<Medication>> _medicationsStream;
  late Timer _clock;

  DateTime _now = DateTime.now();
  String? _busyMedicationId;

  @override
  void initState() {
    super.initState();
    _medicationsStream = _medicationService.getTodayMedications();
    // Keeps the "now" marker and the remaining-time labels honest.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _medicationsStream = _medicationService.getTodayMedications();
      _now = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<Medication>>(
                stream: _medicationsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingState();
                  }
                  if (snapshot.hasError) {
                    return _buildErrorState(snapshot.error);
                  }
                  final medications = snapshot.data ?? const <Medication>[];
                  if (medications.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildTimeline(medications);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptions,
        backgroundColor: AppColors.primary,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'إضافة دواء',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحقيبة الطبية',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'جدول جرعاتك لهذا اليوم',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white,
                  size: 13,
                ),
                const SizedBox(width: 7),
                Text(
                  _formattedToday(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: const [
        _Skeleton(height: 96),
        SizedBox(height: 22),
        _Skeleton(height: 132),
        SizedBox(height: 14),
        _Skeleton(height: 132),
        SizedBox(height: 14),
        _Skeleton(height: 132),
      ],
    );
  }

  Widget _buildErrorState(Object? error) {
    debugPrint('Medical kit stream error: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'تعذّر تحميل أدويتك',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _reload,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_liquid_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'لا توجد أدوية مجدولة اليوم',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أضف أدويتك لتصلك جرعاتك في جدول زمني واضح طوال اليوم.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.7),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _showAddOptions,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('أضف أول دواء'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline
  // ---------------------------------------------------------------------------

  Widget _buildTimeline(List<Medication> medications) {
    final slots = _buildSlots(medications);
    final timedSlots = slots.where((slot) => slot.at != null).toList();
    final flexibleSlots = slots.where((slot) => slot.at == null).toList();

    final items = <_TimelineItem>[];
    var markerAdded = false;
    for (final slot in timedSlots) {
      if (!markerAdded && slot.at!.isAfter(_now)) {
        items.add(const _NowItem());
        markerAdded = true;
      }
      items.add(_DoseItem(slot));
    }
    if (!markerAdded) {
      items.add(const _NowItem());
      markerAdded = true;
    }
    for (final slot in flexibleSlots) {
      items.add(_DoseItem(slot));
    }

    final nextDoseSlot = timedSlots
        .where((slot) => slot.at!.isAfter(_now))
        .fold<DateTime?>(
          null,
          (earliest, slot) =>
              earliest == null || slot.at!.isBefore(earliest) ? slot.at : earliest,
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 120),
      children: [
        _buildDaySummary(timedSlots, flexibleSlots),
        const SizedBox(height: 26),
        for (var index = 0; index < items.length; index++)
          _buildTimelineRow(
            item: items[index],
            isLast: index == items.length - 1,
            nextDoseAt: nextDoseSlot,
          ),
      ],
    );
  }

  Widget _buildDaySummary(
    List<_DoseSlot> timedSlots,
    List<_DoseSlot> flexibleSlots,
  ) {
    final total = timedSlots.length;
    int countOf(_DoseState state) =>
        timedSlots.where((slot) => _stateForDose(slot) == state).length;
    final taken = countOf(_DoseState.taken);
    final pending = countOf(_DoseState.pending);
    final upcoming = countOf(_DoseState.upcoming);
    final skipped = countOf(_DoseState.skipped) + countOf(_DoseState.missed);
    final percent = total == 0 ? 0 : ((taken / total) * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'خطة اليوم',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      total == 0
                          ? 'لا توجد جرعات مجدولة بأوقات'
                          : 'أُخذت $taken من $total جرعة',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.07),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    width: 1.4,
                  ),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : taken / total,
              minHeight: 8,
              backgroundColor: const Color(0xFFEDF2F9),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _legendDot(const Color(0xFF16A34A), 'مكتملة', taken),
              _legendDot(const Color(0xFFF59E0B), 'بانتظار', pending),
              _legendDot(const Color(0xFF1A73E8), 'قادمة', upcoming),
              if (skipped > 0)
                _legendDot(const Color(0xFF94A3B8), 'متخطاة', skipped),
              if (flexibleSlots.isNotEmpty)
                _legendDot(
                  const Color(0xFF64748B),
                  'عند الحاجة',
                  flexibleSlots.length,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow({
    required _TimelineItem item,
    required bool isLast,
    required DateTime? nextDoseAt,
  }) {
    switch (item) {
      case _DoseItem(:final slot):
        final state = _stateForDose(slot);
        final clock = slot.at != null ? _clockFromDate(slot.at!) : null;
        final inCurrentHour = slot.at != null &&
            slot.at!.hour == _now.hour &&
            slot.at!.day == _now.day;

        return _timelineRow(
          isLast: isLast,
          timeTop: clock?.clock ?? 'عند',
          timeBottom: clock?.period ?? 'الحاجة',
          timeHighlighted: inCurrentHour && state != _DoseState.taken,
          node: _TimelineNode(state: state),
          card: _buildDoseCard(slot, state),
        );
      case _NowItem():
        final clock = _clockFromDate(_now);
        return _timelineRow(
          isLast: isLast,
          timeTop: 'الآن',
          timeBottom: clock.clock,
          timeHighlighted: true,
          node: const _NowNode(),
          card: _buildNowCard(nextDoseAt),
        );
    }
  }

  static const double _timeColumnWidth = 54;
  static const double _railWidth = 26;

  Widget _timelineRow({
    required bool isLast,
    required String timeTop,
    required String timeBottom,
    required bool timeHighlighted,
    required Widget node,
    required Widget card,
  }) {
    // Painted behind the node so the rail is continuous regardless of the
    // card's height, without the cost of IntrinsicHeight.
    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: _timeColumnWidth + _railWidth / 2 - 1,
            top: 20,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFE1E8F2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Row(
          // Pinned to LTR so the rail always sits on the visual left, while the
          // card content keeps the app's RTL reading direction.
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeColumnWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeTop,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: timeHighlighted
                            ? AppColors.primary
                            : AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeBottom,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: timeHighlighted
                            ? AppColors.primary.withValues(alpha: 0.7)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _railWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Center(child: node),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 4,
                  bottom: isLast ? 0 : 14,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: card,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNowCard(DateTime? nextDoseAt) {
    final remaining = nextDoseAt?.difference(_now);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الوقت الحالي',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                if (remaining != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'الجرعة القادمة ${_remainingText(remaining)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A7BC8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoseCard(_DoseSlot slot, _DoseState state) {
    final medication = slot.medication;
    final palette = _paletteFor(medication.type);
    final actionable = medication.status == MedicationStatus.pending;
    final busy = _busyMedicationId == medication.id;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        borderColor: state == _DoseState.upcoming
            ? AppColors.primary.withValues(alpha: 0.14)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  medication.typeIcon,
                  color: palette.foreground,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${medication.dosage} · ${medication.typeDisplay}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (medication.instructions != null &&
              medication.instructions!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.restaurant_menu_rounded,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    medication.instructions!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Wrap keeps the badge and the action usable on narrow screens.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusBadge(state: state, remaining: _remainingFor(slot, state)),
              if (actionable)
                _MarkTakenButton(
                  busy: busy,
                  onPressed: busy ? null : () => _markAsTaken(medication),
                )
              else
                _takenCaption(medication, state),
            ],
          ),
        ],
      ),
    );
  }

  Widget _takenCaption(Medication medication, _DoseState state) {
    if (state != _DoseState.taken) return const SizedBox.shrink();
    final takenAt = medication.lastTakenAt;
    if (takenAt == null || takenAt.day != _now.day) {
      return const SizedBox.shrink();
    }
    final clock = _clockFromDate(takenAt);
    return Text(
      'سُجّلت ${clock.clock} ${clock.period}',
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF94A3B8),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  List<_DoseSlot> _buildSlots(List<Medication> medications) {
    final timed = <_DoseSlot>[];
    final flexible = <_DoseSlot>[];

    for (final medication in medications) {
      var scheduled = false;
      for (final time in medication.scheduledTimes) {
        final at = _timeForToday(time);
        if (at == null) continue;
        scheduled = true;
        timed.add(_DoseSlot(medication: medication, at: at));
      }
      // As-needed doses (or unparsable times) still deserve a place on the rail.
      if (!scheduled) {
        flexible.add(_DoseSlot(medication: medication, at: null));
      }
    }

    timed.sort((a, b) => a.at!.compareTo(b.at!));
    flexible.sort((a, b) => a.medication.name.compareTo(b.medication.name));
    return [...timed, ...flexible];
  }

  DateTime? _timeForToday(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(_now.year, _now.month, _now.day, hour, minute);
  }

  _DoseState _stateForDose(_DoseSlot slot) {
    switch (slot.medication.status) {
      case MedicationStatus.taken:
        return _DoseState.taken;
      case MedicationStatus.skipped:
        return _DoseState.skipped;
      case MedicationStatus.missed:
        return _DoseState.missed;
      case MedicationStatus.pending:
        if (slot.at == null) return _DoseState.upcoming;
        return slot.at!.isAfter(_now)
            ? _DoseState.upcoming
            : _DoseState.pending;
    }
  }

  Duration? _remainingFor(_DoseSlot slot, _DoseState state) {
    if (state != _DoseState.upcoming || slot.at == null) return null;
    final remaining = slot.at!.difference(_now);
    return remaining.isNegative ? null : remaining;
  }

  String _remainingText(Duration difference) {
    final minutes = difference.inMinutes;
    if (minutes <= 1) return 'بعد لحظات';
    if (minutes < 60) return 'بعد $minutes دقيقة';
    final hours = difference.inHours;
    final rest = minutes - hours * 60;
    final hourLabel = switch (hours) {
      1 => 'ساعة',
      2 => 'ساعتين',
      _ => '$hours ساعات',
    };
    if (rest == 0) return 'بعد $hourLabel';
    return 'بعد $hourLabel و$rest دقيقة';
  }

  ({String clock, String period}) _clockFromDate(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return (
      clock: '$hour:${date.minute.toString().padLeft(2, '0')}',
      period: date.hour < 12 ? 'ص' : 'م',
    );
  }

  String _formattedToday() {
    const weekdays = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${weekdays[_now.weekday - 1]} · ${_now.day} ${months[_now.month - 1]} ${_now.year}';
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? const Color(0xFFF0F4F9),
        width: borderColor == null ? 1 : 1.4,
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Pastel container colour plus a matching icon colour per medication form.
  ({Color background, Color foreground}) _paletteFor(MedicationType type) {
    return switch (type) {
      MedicationType.tablet => (
        background: const Color(0xFFE8F0FE),
        foreground: const Color(0xFF1A73E8),
      ),
      MedicationType.capsule => (
        background: const Color(0xFFF1EAFE),
        foreground: const Color(0xFF7C3AED),
      ),
      MedicationType.injection => (
        background: const Color(0xFFFFE9EE),
        foreground: const Color(0xFFE11D48),
      ),
      MedicationType.syrup => (
        background: const Color(0xFFFFF3E0),
        foreground: const Color(0xFFD97706),
      ),
      MedicationType.drops => (
        background: const Color(0xFFE0F5F9),
        foreground: const Color(0xFF0891B2),
      ),
      MedicationType.inhaler => (
        background: const Color(0xFFE4F6F1),
        foreground: const Color(0xFF0D9488),
      ),
      MedicationType.cream => (
        background: const Color(0xFFEDF7E3),
        foreground: const Color(0xFF4D7C0F),
      ),
      MedicationType.other => (
        background: const Color(0xFFEEF2F7),
        foreground: const Color(0xFF475569),
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _markAsTaken(Medication medication) async {
    if (_busyMedicationId != null) return;
    setState(() => _busyMedicationId = medication.id);
    try {
      await _medicationService.markAsTaken(medication.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الجرعة ✓'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      debugPrint('Mark as taken failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر تحديث الحالة: $error'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyMedicationId = null);
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'إضافة دواء',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: AppColors.primary.withValues(alpha: 0.06),
              leading: const Icon(Icons.document_scanner_rounded, color: AppColors.primary),
              title: const Text('مسح وصفة طبية (OCR)'),
              subtitle: const Text('التقاط صورة وتحليلها بالذكاء الاصطناعي'),
              onTap: () {
                Navigator.pop(context);
                _scanPrescription();
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: AppColors.accent.withValues(alpha: 0.06),
              leading: const Icon(Icons.edit_rounded, color: AppColors.accent),
              title: const Text('إضافة يدوياً'),
              subtitle: const Text('إدخال بيانات الدواء يدوياً'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddMedicationScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Prescription OCR flow (unchanged behaviour)
  // ---------------------------------------------------------------------------

  Future<void> _scanPrescription() async {
    try {
      final imageUrl = await _ocrService.pickImage(source: ImageSource.camera);

      if (imageUrl == null) return;
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final parsedData = await _ocrService.parsePrescription(imageUrl);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (parsedData['detected_duration'] == null) {
        _showDurationSelectionDialog(parsedData, imageUrl);
      } else {
        final duration = parsedData['duration_days'] as int;
        _createMedicationsFromOCR(parsedData, duration, imageUrl);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDurationSelectionDialog(
    Map<String, dynamic> parsedData,
    String imageUrl,
  ) {
    showDialog(
      context: context,
      builder: (context) => DurationSelectionDialog(
        onDurationSelected: (days) {
          Navigator.pop(context);
          _createMedicationsFromOCR(parsedData, days, imageUrl);
        },
      ),
    );
  }

  Future<void> _createMedicationsFromOCR(
    Map<String, dynamic> parsedData,
    int durationDays,
    String imageUrl,
  ) async {
    try {
      final meds = parsedData['medications'] as List;

      for (final medData in meds) {
        final medication = _ocrService.createMedicationFromParsedData(
          {'medications': [medData], 'imageUrl': imageUrl},
          durationDays,
        );

        await _medicationService.addMedication(medication);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة ${meds.length} دواء بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Timeline pieces
// -----------------------------------------------------------------------------

enum _DoseState { taken, skipped, missed, pending, upcoming }

class _DoseSlot {
  const _DoseSlot({required this.medication, required this.at});

  final Medication medication;

  /// Scheduled time today, or `null` for an as-needed dose.
  final DateTime? at;
}

sealed class _TimelineItem {
  const _TimelineItem();
}

class _DoseItem extends _TimelineItem {
  const _DoseItem(this.slot);
  final _DoseSlot slot;
}

class _NowItem extends _TimelineItem {
  const _NowItem();
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.state});

  final _DoseState state;

  Color get _color => switch (state) {
    _DoseState.taken => const Color(0xFF16A34A),
    _DoseState.pending => const Color(0xFFF59E0B),
    _DoseState.upcoming => const Color(0xFF1A73E8),
    _DoseState.skipped => const Color(0xFF94A3B8),
    _DoseState.missed => const Color(0xFFEF4444),
  };

  IconData? get _icon => switch (state) {
    _DoseState.taken => Icons.check_rounded,
    _DoseState.pending => null,
    _DoseState.upcoming => null,
    _DoseState.skipped => Icons.remove_rounded,
    _DoseState.missed => Icons.close_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: icon == null
          ? Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : Icon(icon, color: Colors.white, size: 11),
    );
  }
}

/// Pulsing node marking the current time on the rail.
class _NowNode extends StatefulWidget {
  const _NowNode();

  @override
  State<_NowNode> createState() => _NowNodeState();
}

class _NowNodeState extends State<_NowNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            // The halo intentionally paints outside the 20px node.
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 20 + 14 * _pulse.value,
                height: 20 + 14 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(
                    alpha: 0.22 * (1 - _pulse.value),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.primary, width: 2.4),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.remaining});

  final _DoseState state;
  final Duration? remaining;

  Color get _color => switch (state) {
    _DoseState.taken => const Color(0xFF16A34A),
    _DoseState.pending => const Color(0xFFD97706),
    _DoseState.upcoming => const Color(0xFF1A73E8),
    _DoseState.skipped => const Color(0xFF64748B),
    _DoseState.missed => const Color(0xFFDC2626),
  };

  IconData get _icon => switch (state) {
    _DoseState.taken => Icons.check_circle_rounded,
    _DoseState.pending => Icons.pending_actions_rounded,
    _DoseState.upcoming => Icons.schedule_rounded,
    _DoseState.skipped => Icons.do_not_disturb_on_rounded,
    _DoseState.missed => Icons.error_rounded,
  };

  String get _label {
    switch (state) {
      case _DoseState.taken:
        return 'تم أخذها';
      case _DoseState.pending:
        return 'قيد الانتظار';
      case _DoseState.skipped:
        return 'تم التخطي';
      case _DoseState.missed:
        return 'فائت';
      case _DoseState.upcoming:
        if (remaining == null) return 'عند الحاجة';
        final minutes = remaining!.inMinutes;
        if (minutes < 60) return 'بعد $minutes دقيقة';
        final hours = remaining!.inHours;
        if (hours == 1) return 'بعد ساعة';
        if (hours == 2) return 'بعد ساعتين';
        return 'بعد $hours ساعات';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _color),
          const SizedBox(width: 5),
          Text(
            _label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkTakenButton extends StatelessWidget {
  const _MarkTakenButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'أخذ الجرعة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F7),
        borderRadius: BorderRadius.circular(16),
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
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 17),
        ),
      ),
    );
  }
}

class DurationSelectionDialog extends StatefulWidget {
  final Function(int) onDurationSelected;

  const DurationSelectionDialog({
    super.key,
    required this.onDurationSelected,
  });

  @override
  State<DurationSelectionDialog> createState() => _DurationSelectionDialogState();
}

class _DurationSelectionDialogState extends State<DurationSelectionDialog> {
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تحديد مدة العلاج'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('لم يتم تحديد مدة العلاج في الوصفة'),
          const SizedBox(height: 16),
          const Text('كم يوماً ستستخدم هذه الأدوية؟'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [7, 14, 30, 60, 90].map((days) {
              final isSelected = _selectedDays == days;
              return ChoiceChip(
                label: Text('$days يوم'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedDays = days;
                  });
                },
                selectedColor: AppColors.primary,
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onDurationSelected(_selectedDays);
          },
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
