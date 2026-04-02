enum LogLevel { debug, info, success, warning, error }

class AppLog {
  final DateTime timestamp;
  final LogLevel level;
  final String context;
  final String message;
  final String? details;

  AppLog({
    required this.timestamp,
    required this.level,
    required this.context,
    required this.message,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'context': context,
    'message': message,
    if (details != null) 'details': details,
  };

  factory AppLog.fromJson(Map<String, dynamic> json) => AppLog(
    timestamp: DateTime.parse(json['timestamp']),
    level: LogLevel.values.firstWhere(
      (l) => l.name == json['level'],
      orElse: () => LogLevel.info,
    ),
    context: json['context'] as String,
    message: json['message'] as String,
    details: json['details'] as String?,
  );

  @override
  String toString() {
    final ts = timestamp
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('T', ' ');
    final lvl = '[${level.name.toUpperCase()}]'.padRight(9);
    final base = '$ts $lvl [$context] $message';
    if (details != null) return '$base\n$details';
    return base;
  }
}
