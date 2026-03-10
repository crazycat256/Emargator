import 'package:timezone/timezone.dart' as tz;

/// A lesson/course from the planning.
class Lesson {
  final String title;
  final DateTime hourStart;
  final DateTime hourEnd;
  final String description;
  final String classroom;

  const Lesson({
    required this.title,
    required this.hourStart,
    required this.hourEnd,
    required this.description,
    required this.classroom,
  });

  /// Create from iCalendar event data.
  factory Lesson.fromIcs(Map<String, dynamic> data) {
    return Lesson(
      title: _getTitle(data),
      hourStart: _getHour(data, 'dtstart'),
      hourEnd: _getHour(data, 'dtend'),
      description: _getDescription(data),
      classroom: _getClassroom(data),
    );
  }

  /// Create from saved JSON.
  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      title: json['title'],
      hourStart: DateTime.fromMillisecondsSinceEpoch(json['hourStart']),
      hourEnd: DateTime.fromMillisecondsSinceEpoch(json['hourEnd']),
      description: json['description'] ?? '',
      classroom: json['classroom'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'hourStart': hourStart.millisecondsSinceEpoch,
    'hourEnd': hourEnd.millisecondsSinceEpoch,
    'description': description,
    'classroom': classroom,
  };

  /// Unique key for this lesson instance (used for overrides).
  String get uid => '${title.hashCode}_${hourStart.millisecondsSinceEpoch}';

  static String _getTitle(Map<String, dynamic> data) {
    return (data['summary'] ?? '').replaceAll('\\', '').trim();
  }

  static DateTime _getHour(Map<String, dynamic> data, String key) {
    try {
      return tz.TZDateTime.parse(tz.local, data[key]['dt']);
    } catch (_) {
      return DateTime.now();
    }
  }

  static String _getDescription(Map<String, dynamic> data) {
    try {
      var ret = (data['description'] ?? '').split('\\n');
      if (ret.length > 4) {
        ret.removeAt(0);
        ret.removeAt(0);
        ret.removeLast();
        ret.removeLast();
      }
      return ret.join(', ').trim();
    } catch (_) {
      return '';
    }
  }

  static String _getClassroom(Map<String, dynamic> data) {
    return (data['location'] ?? '')
        .replaceAll('\\,V-', ', ')
        .replaceAll('V-', '')
        .replaceAll('I-', '')
        .replaceAll('B-', '')
        .replaceAll('L-', '')
        .replaceAll('\\', ' ')
        .replaceAll('TO-', '')
        .trim();
  }
}
