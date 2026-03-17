import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationTimingMode { afterStart, beforeEnd }

class PlanningNotificationRule {
  final int offsetSeconds;
  final NotificationTimingMode timingMode;
  final bool urgent;

  const PlanningNotificationRule({
    required this.offsetSeconds,
    this.timingMode = NotificationTimingMode.afterStart,
    this.urgent = false,
  });

  Map<String, dynamic> toJson() => {
    'offsetSeconds': offsetSeconds,
    'timingMode': timingMode.name,
    'urgent': urgent,
  };

  static PlanningNotificationRule fromJson(Map<String, dynamic> json) {
    final modeRaw = json['timingMode'] as String?;
    final mode = modeRaw == NotificationTimingMode.beforeEnd.name
        ? NotificationTimingMode.beforeEnd
        : NotificationTimingMode.afterStart;
    return PlanningNotificationRule(
      offsetSeconds: json['offsetSeconds'] as int,
      timingMode: mode,
      urgent: (json['urgent'] as bool?) ?? false,
    );
  }
}

/// override status for a specific lesson occurrence or time slot.
enum LessonOverride {
  /// No override — use keyword-based logic.
  none,

  /// Force attendance (ignore keyword match).
  forceAttend,

  /// Skip attendance (even if no keyword match).
  forceSkip,
}

/// Persists the user's planning preferences:
/// - Selected group (formation/year/group names)
/// - Ignore keywords
/// - Per-lesson overrides
class PlanningPrefsService {
  static const _keyFormation = 'planning_formation';
  static const _keyYear = 'planning_year';
  static const _keyGroup = 'planning_group';
  static const _keyKeywords = 'planning_ignore_keywords';
  static const _keyKeywordsInitialized = 'planning_keywords_initialized';
  static const _keyOverrides = 'planning_overrides';
  static const _keyNotifEnabled = 'planning_notif_enabled';
  static const _keyNotifOffsetsSeconds = 'planning_notif_offsets_seconds';
  static const _keyNotifRules = 'planning_notif_rules';

  static const defaultKeywords = ['Activités HACK2G2', 'Activités GCC'];
  static const _slotDurationSeconds = 90 * 60;
  static const defaultNotifOffsetsSeconds = [5, 300, 4500, 5100, 5280];
  static const defaultNotificationRules = [
    PlanningNotificationRule(offsetSeconds: 5),
    PlanningNotificationRule(offsetSeconds: 300),
    PlanningNotificationRule(
      offsetSeconds: 900,
      timingMode: NotificationTimingMode.beforeEnd,
    ),
    PlanningNotificationRule(
      offsetSeconds: 300,
      timingMode: NotificationTimingMode.beforeEnd,
      urgent: true,
    ),
    PlanningNotificationRule(
      offsetSeconds: 120,
      timingMode: NotificationTimingMode.beforeEnd,
      urgent: true,
    ),
  ];

  // ── Group selection ──

  static Future<void> saveGroupSelection({
    required String formation,
    required String year,
    required String group,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_keyFormation, formation);
    prefs.setString(_keyYear, year);
    prefs.setString(_keyGroup, group);
  }

  static Future<({String? formation, String? year, String? group})>
  getGroupSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      formation: prefs.getString(_keyFormation),
      year: prefs.getString(_keyYear),
      group: prefs.getString(_keyGroup),
    );
  }

  static Future<bool> hasGroupSelection() async {
    final sel = await getGroupSelection();
    return sel.formation != null && sel.year != null && sel.group != null;
  }

  static Future<void> clearGroupSelection() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_keyFormation);
    prefs.remove(_keyYear);
    prefs.remove(_keyGroup);
  }

  // ── Ignore keywords ──

  static Future<List<String>> getKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final initialized = prefs.getBool(_keyKeywordsInitialized) ?? false;
    if (!initialized) {
      await prefs.setStringList(_keyKeywords, defaultKeywords);
      await prefs.setBool(_keyKeywordsInitialized, true);
      return List.of(defaultKeywords);
    }
    return prefs.getStringList(_keyKeywords) ?? [];
  }

  static Future<void> setKeywords(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_keyKeywords, keywords);
  }

  // ── Per-lesson overrides ──

  /// Overrides map: lessonUid -> LessonOverride
  static Future<Map<String, LessonOverride>> getOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOverrides);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, LessonOverride.values[v as int]));
    } catch (_) {
      return {};
    }
  }

  static Future<void> setOverride(
    String lessonUid,
    LessonOverride override,
  ) async {
    final overrides = await getOverrides();
    if (override == LessonOverride.none) {
      overrides.remove(lessonUid);
    } else {
      overrides[lessonUid] = override;
    }
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      _keyOverrides,
      jsonEncode(overrides.map((k, v) => MapEntry(k, v.index))),
    );
  }

  static Future<void> clearOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_keyOverrides);
  }

  // ── Notification settings ──

  static Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotifEnabled) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifEnabled, enabled);
  }

  static Future<List<int>> getNotificationOffsetsSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyNotifOffsetsSeconds);
    if (raw == null) return List.of(defaultNotifOffsetsSeconds);

    try {
      final list =
          (jsonDecode(raw) as List)
              .map((e) => e as int)
              .where((e) => e > 0)
              .toSet()
              .toList()
            ..sort();
      if (list.isEmpty) return List.of(defaultNotifOffsetsSeconds);
      return list;
    } catch (_) {
      return List.of(defaultNotifOffsetsSeconds);
    }
  }

  static Future<void> setNotificationOffsetsSeconds(List<int> offsets) async {
    final normalized = offsets.where((e) => e > 0).toSet().toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyNotifOffsetsSeconds,
      jsonEncode(normalized.isEmpty ? defaultNotifOffsetsSeconds : normalized),
    );
  }

  static Future<List<PlanningNotificationRule>> getNotificationRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyNotifRules);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final rules =
            decoded
                .map(
                  (e) => PlanningNotificationRule.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .where((r) => r.offsetSeconds > 0)
                .toList()
              ..sort(_compareByArrival);
        if (rules.isNotEmpty) return rules;
      } catch (_) {}
    }

    // Migration path from legacy offsets-only setting.
    final legacyOffsets = await getNotificationOffsetsSeconds();
    if (legacyOffsets.isNotEmpty) {
      final firstRemainingIndex = legacyOffsets.length > 3
          ? legacyOffsets.length - 3
          : 0;
      final firstUrgentIndex = legacyOffsets.length > 2
          ? legacyOffsets.length - 2
          : 0;
      final migrated = <PlanningNotificationRule>[];
      for (int i = 0; i < legacyOffsets.length; i++) {
        final offset = legacyOffsets[i];
        final urgent = i >= firstUrgentIndex;
        final isLastThree = i >= firstRemainingIndex;
        final mode = isLastThree
            ? NotificationTimingMode.beforeEnd
            : NotificationTimingMode.afterStart;
        final effectiveOffset = mode == NotificationTimingMode.beforeEnd
            ? (_slotDurationSeconds - offset).clamp(1, _slotDurationSeconds)
            : offset;
        migrated.add(
          PlanningNotificationRule(
            offsetSeconds: effectiveOffset,
            timingMode: mode,
            urgent: urgent,
          ),
        );
      }
      await setNotificationRules(migrated);
      return migrated;
    }

    return List.of(defaultNotificationRules);
  }

  static Future<void> setNotificationRules(
    List<PlanningNotificationRule> rules,
  ) async {
    final normalized = rules.where((r) => r.offsetSeconds > 0).toList()
      ..sort(_compareByArrival);
    final prefs = await SharedPreferences.getInstance();
    final target = normalized.isEmpty ? defaultNotificationRules : normalized;
    await prefs.setString(
      _keyNotifRules,
      jsonEncode(target.map((r) => r.toJson()).toList()),
    );
  }

  static int _effectiveOffsetFromStart(PlanningNotificationRule rule) {
    if (rule.timingMode == NotificationTimingMode.afterStart) {
      return rule.offsetSeconds;
    }
    return (_slotDurationSeconds - rule.offsetSeconds).clamp(
      0,
      _slotDurationSeconds,
    );
  }

  static int _compareByArrival(
    PlanningNotificationRule a,
    PlanningNotificationRule b,
  ) {
    final ea = _effectiveOffsetFromStart(a);
    final eb = _effectiveOffsetFromStart(b);
    return ea.compareTo(eb);
  }
}
