import 'dart:convert';

import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/index/ensi_index.dart';
import '../models/index/group.dart';
import '../models/lesson.dart';

class PlanningService {
  static const String _baseUrl = 'planning.univ-ubs.fr';
  static const String _pathUrl =
      '/jsp/custom/modules/plannings/anonymous_cal.jsp';
  static const String _indexUrl =
      'https://raw.githubusercontent.com/matissePe/planning-ubs-index/main/index.json';
  static const String _projectIdUrl =
      'https://raw.githubusercontent.com/matissePe/planning-ubs-index/main/projectid';

  static DateFormat? _dateFmtInstance;
  static bool _tzInitialized = false;
  static bool _localeInitialized = false;

  static Future<void> _ensureLocale() async {
    if (!_localeInitialized) {
      await initializeDateFormatting('fr_FR', null);
      _localeInitialized = true;
    }
  }

  static DateFormat get _dateFmt {
    _dateFmtInstance ??= DateFormat('yyyy-MM-dd', 'fr_FR');
    return _dateFmtInstance!;
  }

  static void _ensureTz() {
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
      _tzInitialized = true;
    }
  }

  /// Fetch the ENSIBS index (formations, years, groups) from GitHub.
  /// Falls back to cached version on failure.
  static Future<void> fetchIndex() async {
    _ensureTz();
    final prefs = await SharedPreferences.getInstance();

    try {
      final response = await http
          .get(Uri.parse(_indexUrl))
          .timeout(const Duration(seconds: 5));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      EnsiIndex.fromJson(json);
      prefs.setString('ensi_index', response.body);
    } catch (_) {
      // Fallback to saved
      final saved = prefs.getString('ensi_index');
      if (saved != null) {
        EnsiIndex.fromJson(jsonDecode(saved));
      }
    }

    // Project ID
    try {
      final response = await http
          .get(Uri.parse(_projectIdUrl))
          .timeout(const Duration(seconds: 5));
      final id = int.parse(response.body.trim());
      EnsiIndex.projectId = id;
      prefs.setInt('ensi_project_id', id);
    } catch (_) {
      EnsiIndex.projectId = prefs.getInt('ensi_project_id') ?? 1;
    }
  }

  /// Fetch the planning for the given [group].
  /// Returns lessons from today onwards, sorted by start time.
  static Future<List<Lesson>?> fetchLessons(EnsiGroup group) async {
    _ensureTz();
    await _ensureLocale();

    final resources = group.adeIds.join(',');
    final uri = Uri.https(_baseUrl, _pathUrl, {
      'projectId': EnsiIndex.projectId.toString(),
      'calType': 'ical',
      'firstDate': _dateFmt.format(tz.TZDateTime.now(tz.local)),
      'lastDate': '2040-12-31',
      'resources': resources,
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = ICalendar.fromString(response.body).toJson()['data'];
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      final lessons = <Lesson>[];
      for (var item in data) {
        final lesson = Lesson.fromIcs(item);
        if (lesson.hourEnd.isAfter(today)) {
          lessons.add(lesson);
        }
      }
      lessons.sort((a, b) => a.hourStart.compareTo(b.hourStart));

      // Cache
      await _saveLessons(group, lessons);

      return lessons;
    } catch (_) {
      return _loadCachedLessons(group);
    }
  }

  static String _cacheKey(EnsiGroup group) =>
      'planning_${group.year.formation.name}_${group.year.name}_${group.name}';

  static Future<void> _saveLessons(
    EnsiGroup group,
    List<Lesson> lessons,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = lessons.map((l) => l.toJson()).toList();
    prefs.setString(_cacheKey(group), jsonEncode(json));
  }

  static Future<List<Lesson>?> _loadCachedLessons(EnsiGroup group) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_cacheKey(group));
    if (saved == null) return null;

    try {
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final list = (jsonDecode(saved) as List)
          .map((j) => Lesson.fromJson(j))
          .where((l) => l.hourEnd.isAfter(today))
          .toList();
      list.sort((a, b) => a.hourStart.compareTo(b.hourStart));
      return list;
    } catch (_) {
      return null;
    }
  }
}
