import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/planning_state.dart';
import '../services/planning_prefs_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  List<PlanningNotificationRule> _rules = [];
  bool _isSaving = false;
  static const _slotDurationSeconds = 90 * 60;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await PlanningPrefsService.getNotificationRules();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _sortRules();
    });
  }

  String _formatDelay(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min}m ${sec}s';
  }

  String _modeSign(NotificationTimingMode mode) {
    return mode == NotificationTimingMode.afterStart ? '+' : '-';
  }

  int _effectiveOffsetFromStart(PlanningNotificationRule rule) {
    if (rule.timingMode == NotificationTimingMode.afterStart) {
      return rule.offsetSeconds;
    }
    return (_slotDurationSeconds - rule.offsetSeconds).clamp(
      0,
      _slotDurationSeconds,
    );
  }

  void _sortRules() {
    _rules.sort((a, b) {
      final ea = _effectiveOffsetFromStart(a);
      final eb = _effectiveOffsetFromStart(b);
      return ea.compareTo(eb);
    });
  }

  int? _parseDelayInput(String input) {
    final raw = input.trim().toLowerCase();
    final m = RegExp(r'^(\d+)\s*(s|sec|secs|m|min|mins)?$').firstMatch(raw);
    if (m == null) return null;
    final number = int.tryParse(m.group(1) ?? '');
    if (number == null || number <= 0) return null;
    final unit = m.group(2) ?? 'm';
    return (unit == 's' || unit == 'sec' || unit == 'secs')
        ? number
        : number * 60;
  }

  Future<PlanningNotificationRule?> _showRuleEditor({
    PlanningNotificationRule? initial,
  }) async {
    final delayCtrl = TextEditingController(
      text: initial == null
          ? '5m'
          : (initial.offsetSeconds < 60
                ? '${initial.offsetSeconds}s'
                : '${initial.offsetSeconds ~/ 60}m'),
    );
    NotificationTimingMode timingMode =
        initial?.timingMode ?? NotificationTimingMode.afterStart;
    bool urgent = initial?.urgent ?? false;

    final result = await showDialog<PlanningNotificationRule>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Ajouter une notification'
                    : 'Modifier la notification',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: delayCtrl,
                      decoration: InputDecoration(
                        labelText:
                            timingMode == NotificationTimingMode.afterStart
                            ? 'Délai après début du créneau'
                            : 'Délai avant fin du créneau',
                        helperText: 'Ex: 30s, 5m, 15m',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<NotificationTimingMode>(
                      initialValue: timingMode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: const [
                        DropdownMenuItem(
                          value: NotificationTimingMode.afterStart,
                          child: Text('Après le début du créneau'),
                        ),
                        DropdownMenuItem(
                          value: NotificationTimingMode.beforeEnd,
                          child: Text('Avant la fin du créneau'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => timingMode = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: urgent,
                      onChanged: (v) => setLocal(() => urgent = v),
                      title: const Text('Urgente'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    final delay = _parseDelayInput(delayCtrl.text);
                    if (delay == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vérifie le délai'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      PlanningNotificationRule(
                        offsetSeconds: delay,
                        timingMode: timingMode,
                        urgent: urgent,
                      ),
                    );
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    delayCtrl.dispose();
    return result;
  }

  Future<void> _saveRules() async {
    final planningState = context.read<PlanningState>();
    setState(() => _isSaving = true);
    await PlanningPrefsService.setNotificationRules(_rules);
    await planningState.rescheduleNotifications();
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration des notifications enregistrée'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_rules.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune notification configurée'),
              ),
            ),
          ..._rules.asMap().entries.map((entry) {
            final i = entry.key;
            final rule = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${_modeSign(rule.timingMode)} ${_formatDelay(rule.offsetSeconds)}',
                ),
                subtitle: Text(rule.urgent ? 'Urgente' : 'Standard'),
                isThreeLine: false,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final edited = await _showRuleEditor(initial: rule);
                        if (edited == null) return;
                        setState(() {
                          _rules[i] = edited;
                          _sortRules();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _rules.removeAt(i)),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final created = await _showRuleEditor();
              if (created == null) return;
              setState(() {
                _rules.add(created);
                _sortRules();
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une notification'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveRules,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
