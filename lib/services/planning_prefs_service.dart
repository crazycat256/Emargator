import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const defaultKeywords = ['Activités HACK2G2', 'Activités GCC'];

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
}
