/// A Moodle attendance session that was self-recorded.
class MoodleSignedSession {
  final DateTime date;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const MoodleSignedSession({
    required this.date,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  /// Key for fast lookup: "YYYY-M-D_H:M"
  String get key =>
      '${date.year}-${date.month}-${date.day}_$startHour:$startMinute';
}
