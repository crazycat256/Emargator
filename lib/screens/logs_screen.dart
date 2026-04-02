import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_log.dart';
import '../services/app_log_service.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  static const _levelColors = <LogLevel, Color>{
    LogLevel.debug: Color(0xFF9E9E9E),
    LogLevel.info: Color(0xFF64B5F6),
    LogLevel.success: Color(0xFF81C784),
    LogLevel.warning: Color(0xFFFFB74D),
    LogLevel.error: Color(0xFFE57373),
  };

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black;
    final dimColor = const Color(0xFF666666);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        title: const Text('Logs', style: TextStyle(color: Colors.white)),
        actions: [
          ListenableBuilder(
            listenable: AppLogService.instance,
            builder: (context, _) => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Effacer les logs',
              onPressed: AppLogService.instance.logs.isEmpty
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Effacer les logs'),
                          content: const Text(
                            'Tous les logs seront supprimés. Continuer ?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Effacer'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) await AppLogService.instance.clear();
                    },
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppLogService.instance,
        builder: (context, _) {
          final logs = AppLogService.instance.logs;
          if (logs.isEmpty) {
            return Center(
              child: Text(
                'Aucun log.',
                style: TextStyle(color: dimColor, fontFamily: 'monospace'),
              ),
            );
          }
          return Stack(
            children: [
              ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 72),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final levelColor = _levelColors[log.level]!;
                  final ts = log.timestamp
                      .toIso8601String()
                      .substring(0, 19)
                      .replaceAll('T', ' ');
                  final tag = log.level.name.toUpperCase().padRight(7);

                  return GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: log.toString()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ligne copiée'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$ts ',
                              style: TextStyle(color: dimColor),
                            ),
                            TextSpan(
                              text: '[$tag] ',
                              style: TextStyle(
                                color: levelColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: log.message,
                              style: const TextStyle(color: Colors.white),
                            ),
                            if (log.details != null) ...[
                              const TextSpan(text: '\n'),
                              TextSpan(
                                text: log.details,
                                style: TextStyle(color: dimColor),
                              ),
                            ],
                          ],
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ListenableBuilder(
                  listenable: AppLogService.instance,
                  builder: (context, _) => FloatingActionButton(
                    mini: true,
                    tooltip: 'Tout copier',
                    onPressed: AppLogService.instance.logs.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(
                                text: AppLogService.instance.exportAsText(),
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Logs copiés dans le presse-papier',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                    child: const Icon(Icons.copy_outlined),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
