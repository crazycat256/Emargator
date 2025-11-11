class AttendanceLog {
  final DateTime timestamp;
  final String result;
  final String message;

  AttendanceLog({
    required this.timestamp,
    required this.result,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'result': result,
    'message': message,
  };

  factory AttendanceLog.fromJson(Map<String, dynamic> json) => AttendanceLog(
    timestamp: DateTime.parse(json['timestamp']),
    result: json['result'],
    message: json['message'],
  );
}
