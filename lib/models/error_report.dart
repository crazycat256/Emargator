class ErrorReport {
  final DateTime timestamp;
  final String deviceModel;
  final String error;
  final String stackTrace;
  final String contextName;

  ErrorReport({
    required this.timestamp,
    required this.deviceModel,
    required this.error,
    required this.stackTrace,
    required this.contextName,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'deviceModel': deviceModel,
    'error': error,
    'stackTrace': stackTrace,
    'contextName': contextName,
  };

  factory ErrorReport.fromJson(Map<String, dynamic> json) => ErrorReport(
    timestamp: DateTime.parse(json['timestamp']),
    deviceModel: json['deviceModel'],
    error: json['error'],
    stackTrace: json['stackTrace'],
    contextName: json['contextName'],
  );

  @override
  String toString() {
    return '''Exception: $contextName
Date: $timestamp
Appareil: $deviceModel
Erreur: $error
Stacktrace:
$stackTrace
''';
  }
}

