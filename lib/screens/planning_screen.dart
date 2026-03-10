import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/lesson.dart';
import '../providers/app_state.dart';
import '../providers/planning_state.dart';
import '../services/planning_prefs_service.dart';
import '../services/time_slot_service.dart';
import 'group_selection_screen.dart';
import 'keyword_settings_screen.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Rebuild every 60 seconds so the red now-indicator moves
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _pixelsPerHour = 55.0;
  static const _firstHour = 8;
  static const _lastHour = 20;
  static const _topPadding = 10.0;
  static const _totalHeight =
      _topPadding + (_lastHour - _firstHour) * _pixelsPerHour + _topPadding;

  static bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlanningState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Mots-clés à ignorer',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KeywordSettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: state.isLoading ? null : () => state.refreshLessons(),
          ),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, PlanningState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.hasGroup) {
      return _buildNoGroup(context);
    }

    if (state.allLessons.isEmpty) {
      return _buildEmpty(context, state);
    }

    return _buildLessonList(context, state);
  }

  Widget _buildNoGroup(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 80, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Aucun groupe sélectionné',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sélectionnez votre groupe de TP pour voir les cours durant lesquels vous devez émarger.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openGroupSelection(context),
              icon: const Icon(Icons.group_add),
              label: const Text('Choisir un groupe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, PlanningState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Aucun cours à venir pour ${state.selectedGroup!.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          _buildGroupChip(context, state),
        ],
      ),
    );
  }

  Widget _buildGroupChip(BuildContext context, PlanningState state) {
    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.swap_horiz, size: 18),
          label: Text(
            '${state.selectedFormation!.name} — ${state.selectedYear!.name} — ${state.selectedGroup!.name}',
          ),
          onPressed: () => _openGroupSelection(context),
        ),
      ],
    );
  }

  Widget _buildLessonList(BuildContext context, PlanningState state) {
    final appState = context.watch<AppState>();
    final dateFormat = DateFormat('EEEE d MMMM', 'fr_FR');
    final timeFormat = DateFormat('HH:mm', 'fr_FR');

    // Group lessons by day
    final dayGroups = <DateTime, List<Lesson>>{};
    for (final l in state.allLessons) {
      final key = DateTime(
        l.hourStart.year,
        l.hourStart.month,
        l.hourStart.day,
      );
      dayGroups.putIfAbsent(key, () => []).add(l);
    }
    final days = dayGroups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildGroupChip(context, state),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => state.refreshLessons(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final entry = days[index];
                return _buildDayTimeline(
                  entry.key,
                  entry.value,
                  state,
                  appState,
                  dateFormat,
                  timeFormat,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayTimeline(
    DateTime day,
    List<Lesson> dayLessons,
    PlanningState state,
    AppState appState,
    DateFormat dateFormat,
    DateFormat timeFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4, left: 8),
          child: Text(
            _capitalize(dateFormat.format(day)),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.blueGrey,
            ),
          ),
        ),
        SizedBox(
          height: _totalHeight,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time scale
                  SizedBox(
                    width: 28,
                    child: Stack(
                      children: [
                        for (int h = _firstHour; h <= _lastHour; h++)
                          Positioned(
                            top:
                                _topPadding +
                                (h - _firstHour) * _pixelsPerHour -
                                7,
                            left: 0,
                            child: Text(
                              '${h}h',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Left half: lesson cards (informational)
                  Expanded(
                    flex: 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int h = _firstHour; h <= _lastHour; h++)
                          Positioned(
                            top:
                                _topPadding + (h - _firstHour) * _pixelsPerHour,
                            left: 0,
                            right: 0,
                            height: 1,
                            child: Container(color: Colors.grey.shade200),
                          ),
                        for (final lesson in dayLessons)
                          _buildPositionedLesson(lesson, state, timeFormat),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Right half: time slots (interactive)
                  Expanded(
                    flex: 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int h = _firstHour; h <= _lastHour; h++)
                          Positioned(
                            top:
                                _topPadding + (h - _firstHour) * _pixelsPerHour,
                            left: 0,
                            right: 0,
                            height: 1,
                            child: Container(color: Colors.grey.shade200),
                          ),
                        for (final slot in TimeSlotService.slots)
                          _buildPositionedSlot(day, slot, state, appState),
                      ],
                    ),
                  ),
                ],
              ),
              // Red current-time indicator (full width)
              if (_isToday(day)) _buildNowIndicator(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPositionedLesson(
    Lesson lesson,
    PlanningState state,
    DateFormat timeFormat,
  ) {
    final startMin = lesson.hourStart.hour * 60 + lesson.hourStart.minute;
    final endMin = lesson.hourEnd.hour * 60 + lesson.hourEnd.minute;
    final top =
        _topPadding + (startMin - _firstHour * 60) / 60 * _pixelsPerHour;
    final height = max((endMin - startMin) / 60 * _pixelsPerHour, 30.0);
    final isIgnored = state.isLessonIgnoredByKeyword(lesson);

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 1),
        elevation: 0.5,
        color: isIgnored ? Colors.grey.shade100 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lesson.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: height < 60 ? 10 : 12,
                  decoration: isIgnored ? TextDecoration.lineThrough : null,
                  color: isIgnored ? Colors.grey : null,
                ),
                maxLines: height < 60 ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (height >= 50)
                Text(
                  '${timeFormat.format(lesson.hourStart)} – ${timeFormat.format(lesson.hourEnd)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: isIgnored ? Colors.grey.shade400 : Colors.black45,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPositionedSlot(
    DateTime day,
    TimeSlot slot,
    PlanningState state,
    AppState appState,
  ) {
    final startMin = slot.startHour * 60 + slot.startMinute;
    final endMin = slot.endHour * 60 + slot.endMinute;
    final top =
        _topPadding + (startMin - _firstHour * 60) / 60 * _pixelsPerHour;
    final height = (endMin - startMin) / 60 * _pixelsPerHour;

    final mustAttend = state.shouldAttendSlot(day, slot);
    final ovr = state.getSlotOverride(day, slot);
    final isSigned = _isSlotSigned(day, slot, appState);
    final isPast = slot.getEndTime(day).isBefore(DateTime.now());
    final isNow =
        slot.contains(DateTime.now()) &&
        day.year == DateTime.now().year &&
        day.month == DateTime.now().month &&
        day.day == DateTime.now().day;
    final moodleLoaded = appState.moodleDataLoaded;

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: _SlotCard(
        slot: slot,
        mustAttend: mustAttend,
        slotOverride: ovr,
        isSigned: isSigned,
        isPast: isPast,
        isNow: isNow,
        moodleLoaded: moodleLoaded,
        onToggle: () => state.toggleSlotOverride(day, slot),
      ),
    );
  }

  static bool _isSlotSigned(DateTime day, TimeSlot slot, AppState appState) {
    final slotStart = slot.getStartTime(day);
    final slotEnd = slot.getEndTime(day);
    final localSigned = appState.logs.any((log) {
      final inRange =
          !log.timestamp.isBefore(slotStart) && !log.timestamp.isAfter(slotEnd);
      return inRange &&
          (log.result == 'success' || log.result == 'alreadySignedIn');
    });
    if (localSigned) return true;
    return appState.isSlotSignedOnMoodle(day, slot);
  }

  void _openGroupSelection(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GroupSelectionScreen()));
  }

  /// Red current-time indicator: dot on scale + line across full width.
  static Widget _buildNowIndicator() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final top = _topPadding + (nowMin - _firstHour * 60) / 60 * _pixelsPerHour;
    return Positioned(
      top: top - 4,
      left: 0,
      right: 0,
      height: 8,
      child: Row(
        children: [
          // Dot on the scale
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          // Line across both halves
          Expanded(child: Container(height: 1.5, color: Colors.red)),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Slot card (right half, interactive) ───

class _SlotCard extends StatelessWidget {
  final TimeSlot slot;
  final bool mustAttend;
  final LessonOverride slotOverride;
  final bool isSigned;
  final bool isPast;
  final bool isNow;
  final bool moodleLoaded;
  final VoidCallback onToggle;

  const _SlotCard({
    required this.slot,
    required this.mustAttend,
    required this.slotOverride,
    required this.isSigned,
    required this.isPast,
    required this.isNow,
    required this.moodleLoaded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    BorderSide border = BorderSide.none;

    if (isSigned) {
      bgColor = Colors.green.shade100;
      border = BorderSide(color: Colors.green.shade400, width: 1.5);
    } else if (isPast) {
      bgColor = Colors.grey.shade50;
    } else if (isNow && mustAttend) {
      bgColor = Colors.orange.shade50;
      border = const BorderSide(color: Colors.orange, width: 2);
    } else if (mustAttend) {
      bgColor = Colors.blue.shade50;
    } else {
      bgColor = Colors.grey.shade100;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 1),
      elevation: mustAttend && !isPast ? 2 : 0.5,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: border,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (isPast || isSigned) ? null : onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.getTimeRange(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: mustAttend ? null : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLabel(),
                      style: TextStyle(fontSize: 10, color: _statusColor()),
                    ),
                  ],
                ),
              ),
              _buildIcon(),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether this past slot has unknown sign-in status (no local log, no moodle data yet).
  bool get _isPastUnknown => isPast && mustAttend && !isSigned && !moodleLoaded;

  String _statusLabel() {
    if (isSigned) return 'Émargé';
    if (_isPastUnknown) return 'Chargement…';
    if (isPast && mustAttend) return 'Non émargé';
    if (isPast) return 'Passé';
    if (slotOverride == LessonOverride.forceAttend) return 'A émarger';
    if (slotOverride == LessonOverride.forceSkip) return 'Ignoré';
    if (mustAttend) return 'À émarger';
    return 'Pas d\'émargement';
  }

  Color _statusColor() {
    if (isSigned) return Colors.green.shade700;
    if (_isPastUnknown) return Colors.grey;
    if (isPast && mustAttend) return Colors.red.shade300;
    if (isPast) return Colors.grey;
    if (slotOverride == LessonOverride.forceAttend) return Colors.orange;
    if (slotOverride == LessonOverride.forceSkip) return Colors.red;
    if (mustAttend) return Colors.blue;
    return Colors.grey;
  }

  Widget _buildIcon() {
    if (isSigned) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 20);
    }
    if (_isPastUnknown) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isPast && mustAttend) {
      return Icon(Icons.cancel_outlined, color: Colors.red.shade300, size: 20);
    }
    if (isPast) {
      return const Icon(
        Icons.remove_circle_outline,
        color: Colors.grey,
        size: 18,
      );
    }
    if (slotOverride == LessonOverride.forceAttend) {
      return const Icon(Icons.push_pin, color: Colors.orange, size: 20);
    }
    if (slotOverride == LessonOverride.forceSkip) {
      return const Icon(Icons.block, color: Colors.red, size: 20);
    }
    if (mustAttend) {
      return const Icon(
        Icons.radio_button_unchecked,
        color: Colors.blue,
        size: 20,
      );
    }
    return const Icon(
      Icons.remove_circle_outline,
      color: Colors.grey,
      size: 18,
    );
  }
}
