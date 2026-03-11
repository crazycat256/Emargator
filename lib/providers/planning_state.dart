import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/index/ensi_index.dart';
import '../models/index/formation.dart';
import '../models/index/group.dart';
import '../models/index/year.dart';
import '../models/lesson.dart';
import '../services/planning_service.dart';
import '../services/planning_prefs_service.dart';
import '../services/attendance_notification_service.dart';
import '../services/time_slot_service.dart';

/// Manages the planning / attendance-reminder state.
class PlanningState extends ChangeNotifier {
  bool _isLoading = false;
  bool _indexLoaded = false;
  Completer<void>? _schedulingLock;

  // Selection
  EnsiFormation? _selectedFormation;
  EnsiYear? _selectedYear;
  EnsiGroup? _selectedGroup;

  // Data
  List<Lesson> _lessons = [];
  List<String> _keywords = [];
  Map<String, LessonOverride> _overrides = {};

  // Getters
  bool get isLoading => _isLoading;
  bool get indexLoaded => _indexLoaded;
  List<EnsiFormation> get formations => EnsiIndex.formations;
  EnsiFormation? get selectedFormation => _selectedFormation;
  EnsiYear? get selectedYear => _selectedYear;
  EnsiGroup? get selectedGroup => _selectedGroup;
  bool get hasGroup => _selectedGroup != null;
  List<Lesson> get allLessons => _lessons;
  List<String> get keywords => _keywords;
  Map<String, LessonOverride> get overrides => _overrides;

  // ── Keyword matching (lesson-level) ──

  /// Whether a lesson title matches any ignore keyword.
  bool isLessonIgnoredByKeyword(Lesson lesson) {
    final titleLower = lesson.title.toLowerCase();
    for (final kw in _keywords) {
      if (kw.isNotEmpty && titleLower.contains(kw.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  // ── Slot-level attendance logic ──

  /// Get the override for a slot on a given date.
  LessonOverride getSlotOverride(DateTime date, TimeSlot slot) {
    return _overrides[slot.keyForDate(date)] ?? LessonOverride.none;
  }

  /// Whether a slot on a given date requires attendance.
  /// Without override: true if at least one overlapping lesson is NOT ignored by keyword.
  bool shouldAttendSlot(DateTime date, TimeSlot slot) {
    final ovr = _overrides[slot.keyForDate(date)];
    if (ovr == LessonOverride.forceAttend) return true;
    if (ovr == LessonOverride.forceSkip) return false;

    // Auto: check if any overlapping lesson is not keyword-ignored
    final slotStart = slot.getStartTime(date);
    final slotEnd = slot.getEndTime(date);
    for (final lesson in _lessons) {
      if (lesson.hourStart.isBefore(slotEnd) &&
          lesson.hourEnd.isAfter(slotStart)) {
        if (!isLessonIgnoredByKeyword(lesson)) return true;
      }
    }
    return false;
  }

  /// Auto decision for a slot (ignoring override).
  bool autoShouldAttendSlot(DateTime date, TimeSlot slot) {
    final slotStart = slot.getStartTime(date);
    final slotEnd = slot.getEndTime(date);
    for (final lesson in _lessons) {
      if (lesson.hourStart.isBefore(slotEnd) &&
          lesson.hourEnd.isAfter(slotStart)) {
        if (!isLessonIgnoredByKeyword(lesson)) return true;
      }
    }
    return false;
  }

  /// Toggle slot override.
  Future<void> toggleSlotOverride(DateTime date, TimeSlot slot) async {
    final key = slot.keyForDate(date);
    final current = _overrides[key] ?? LessonOverride.none;
    if (current != LessonOverride.none) {
      await _setSlotOverride(key, LessonOverride.none);
    } else {
      final auto = autoShouldAttendSlot(date, slot);
      await _setSlotOverride(
        key,
        auto ? LessonOverride.forceSkip : LessonOverride.forceAttend,
      );
    }
  }

  Future<void> _setSlotOverride(String key, LessonOverride override) async {
    await PlanningPrefsService.setOverride(key, override);
    if (override == LessonOverride.none) {
      _overrides.remove(key);
    } else {
      _overrides[key] = override;
    }
    _scheduleNotifications();
    notifyListeners();
  }

  /// Backward compat: old per-lesson method (used by notifications).
  bool shouldAttend(Lesson lesson) {
    final slots = TimeSlotService.getOverlappingSlots(
      lesson.hourStart,
      lesson.hourEnd,
    );
    final date = DateTime(
      lesson.hourStart.year,
      lesson.hourStart.month,
      lesson.hourStart.day,
    );
    return slots.any((s) => shouldAttendSlot(date, s));
  }

  /// Lessons that require attendance (for notifications).
  List<Lesson> get attendanceLessons {
    return _lessons.where((l) => shouldAttend(l)).toList();
  }

  /// Initialize: load index + restore saved selection.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await PlanningService.fetchIndex();
      _indexLoaded = EnsiIndex.formations.isNotEmpty;

      // Restore saved preferences
      _keywords = await PlanningPrefsService.getKeywords();
      _overrides = await PlanningPrefsService.getOverrides();

      // Restore saved group selection
      final sel = await PlanningPrefsService.getGroupSelection();
      if (sel.formation != null && sel.year != null && sel.group != null) {
        _restoreSelection(sel.formation!, sel.year!, sel.group!);
        if (_selectedGroup != null) {
          await _fetchLessons();
        }
      }
    } catch (e) {
      debugPrint('PlanningState.initialize error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void _restoreSelection(
    String formationName,
    String yearName,
    String groupName,
  ) {
    for (final f in EnsiIndex.formations) {
      if (f.name == formationName) {
        _selectedFormation = f;
        for (final y in f.years) {
          if (y.name == yearName) {
            _selectedYear = y;
            for (final g in y.groups) {
              if (g.name == groupName) {
                _selectedGroup = g;
                return;
              }
            }
          }
        }
      }
    }
  }

  /// Select a group and fetch its planning.
  Future<void> selectGroup(
    EnsiFormation formation,
    EnsiYear year,
    EnsiGroup group,
  ) async {
    _selectedFormation = formation;
    _selectedYear = year;
    _selectedGroup = group;

    await PlanningPrefsService.saveGroupSelection(
      formation: formation.name,
      year: year.name,
      group: group.name,
    );

    _isLoading = true;
    notifyListeners();

    try {
      await _fetchLessons();
    } catch (e) {
      debugPrint('PlanningState.selectGroup error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Clear group selection.
  Future<void> clearGroup() async {
    _selectedFormation = null;
    _selectedYear = null;
    _selectedGroup = null;
    _lessons = [];
    await PlanningPrefsService.clearGroupSelection();
    await AttendanceNotificationService.cancelAll();
    notifyListeners();
  }

  /// Refresh lessons from network.
  Future<void> refreshLessons() async {
    if (_selectedGroup == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      await _fetchLessons();
    } catch (e) {
      debugPrint('PlanningState.refreshLessons error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Update ignore keywords.
  Future<void> setKeywords(List<String> keywords) async {
    _keywords = keywords.where((k) => k.trim().isNotEmpty).toList();
    await PlanningPrefsService.setKeywords(_keywords);
    _scheduleNotifications();
    notifyListeners();
  }

  /// Add a keyword.
  Future<void> addKeyword(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _keywords.add(keyword.trim());
    await PlanningPrefsService.setKeywords(_keywords);
    _scheduleNotifications();
    notifyListeners();
  }

  /// Remove a keyword.
  Future<void> removeKeyword(String keyword) async {
    _keywords.remove(keyword);
    await PlanningPrefsService.setKeywords(_keywords);
    _scheduleNotifications();
    notifyListeners();
  }

  // ── Public ──

  /// Reschedule notifications (call when signed-in state changes externally).
  Future<void> rescheduleNotifications() => _scheduleNotifications();

  // ── Private ──

  Future<void> _fetchLessons() async {
    if (_selectedGroup == null) return;

    final lessons = await PlanningService.fetchLessons(_selectedGroup!);
    _lessons = lessons ?? [];
    // Fire-and-forget: don't block UI on notification scheduling
    _scheduleNotifications();
  }

  Future<void> _scheduleNotifications() async {
    // Wait for any in-progress scheduling to finish before starting a new one
    while (_schedulingLock != null) {
      await _schedulingLock!.future;
    }
    _schedulingLock = Completer<void>();
    try {
      final now = DateTime.now();
      // Android limits to 500 concurrent alarms.
      // Only schedule for the next 7 days to stay well under that.
      final horizon = now.add(const Duration(days: 7));

      // Collect unique (date, slot) pairs that need attendance and are in the future
      final slotsToAttend = <({DateTime date, TimeSlot slot})>[];
      final seen = <String>{};

      for (final lesson in _lessons) {
        if (lesson.hourEnd.isBefore(now)) continue;
        if (lesson.hourStart.isAfter(horizon)) continue;
        if (!shouldAttend(lesson)) continue;

        final date = DateTime(
          lesson.hourStart.year,
          lesson.hourStart.month,
          lesson.hourStart.day,
        );
        final overlapping = TimeSlotService.getOverlappingSlots(
          lesson.hourStart,
          lesson.hourEnd,
        );
        for (final slot in overlapping) {
          if (!shouldAttendSlot(date, slot)) continue;
          if (slot.getEndTime(date).isBefore(now)) continue;
          if (slot.getStartTime(date).isAfter(horizon)) continue;
          final key = slot.keyForDate(date);
          if (seen.add(key)) {
            slotsToAttend.add((date: date, slot: slot));
          }
        }
      }

      // Read signed keys from cache (same SharedPreferences key as AppState)
      final prefs = await SharedPreferences.getInstance();
      final cachedList = prefs.getStringList('moodle_signed_keys');
      final signedKeys = cachedList?.toSet() ?? <String>{};

      await AttendanceNotificationService.scheduleForSlots(
        slotsToAttend: slotsToAttend,
        signedSlotKeys: signedKeys,
      );
    } catch (e) {
      debugPrint('Notification scheduling failed: $e');
    } finally {
      _schedulingLock!.complete();
      _schedulingLock = null;
    }
  }
}
