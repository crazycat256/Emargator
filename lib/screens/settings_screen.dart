import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/planning_state.dart';
import '../services/planning_prefs_service.dart';
import 'about_screen.dart';
import 'group_selection_screen.dart';
import 'keyword_settings_screen.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _hasExistingCredentials = false;
  bool _hasUnsavedChanges = false;
  String _initialStudentId = '';
  bool _isInitialized = false;
  bool _notifEnabled = true;
  int _notifCount = 0;
  int _urgentNotifCount = 0;

  @override
  void initState() {
    super.initState();
    _loadExistingStudentId();
    _studentIdController.addListener(_checkForChanges);
    _passwordController.addListener(_checkForChanges);
  }

  void _checkForChanges() {
    if (!_isInitialized) return;

    final hasChanges =
        _studentIdController.text != _initialStudentId ||
        _passwordController.text.isNotEmpty;
    if (hasChanges != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = hasChanges);
    }
  }

  Future<void> _loadExistingStudentId() async {
    final appState = context.read<AppState>();
    final studentId = await appState.getStudentId();
    final notifEnabled = await PlanningPrefsService.getNotificationsEnabled();
    final notifRules = await PlanningPrefsService.getNotificationRules();
    final notifCount = notifRules.length;
    final urgentCount = notifRules.where((r) => r.urgent).length;
    setState(() {
      if (studentId != null) {
        _studentIdController.text = studentId;
        _initialStudentId = studentId;
        _hasExistingCredentials = true;
      }
      _notifEnabled = notifEnabled;
      _notifCount = notifCount;
      _urgentNotifCount = urgentCount;
      _isInitialized = true;
    });
  }

  Future<void> _reloadNotificationSummary() async {
    final notifEnabled = await PlanningPrefsService.getNotificationsEnabled();
    final notifRules = await PlanningPrefsService.getNotificationRules();
    if (!mounted) return;
    setState(() {
      _notifEnabled = notifEnabled;
      _notifCount = notifRules.length;
      _urgentNotifCount = notifRules.where((r) => r.urgent).length;
    });
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final planningState = context.read<PlanningState>();
    setState(() => _notifEnabled = enabled);
    await PlanningPrefsService.setNotificationsEnabled(enabled);
    await planningState.rescheduleNotifications();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled ? 'Notifications activées' : 'Notifications désactivées',
        ),
        backgroundColor: enabled ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await context.read<AppState>().saveCredentials(
      _studentIdController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identifiants enregistrés avec succès'),
          backgroundColor: Colors.green,
        ),
      );
      _passwordController.clear();
      setState(() {
        _hasExistingCredentials = true;
        _initialStudentId = _studentIdController.text;
        _hasUnsavedChanges = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec de la vérification des identifiants'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
            tooltip: 'À propos',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.settings, size: 80, color: Colors.blue),
              const SizedBox(height: 32),
              const Text(
                'Identifiants UBS',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _studentIdController,
                decoration: const InputDecoration(
                  labelText: 'Numéro d\'étudiant',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  helperText: 'Votre numéro d\'étudiant (ex: e1234567)',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  helperText: _hasExistingCredentials
                      ? 'Laisser vide pour garder le mot de passe actuel'
                      : 'Votre mot de passe UBS',
                ),
                obscureText: true,
                validator: (value) {
                  if (!_hasExistingCredentials && (value?.isEmpty ?? true)) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_isLoading || !_hasUnsavedChanges)
                    ? null
                    : _saveCredentials,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enregistrer'),
              ),
              if (_hasExistingCredentials) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showClearConfirmation(),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer les identifiants'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],

              // ── Planning / Group section ──
              const SizedBox(height: 40),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Planning & Émargement',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildPlanningSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanningSection(BuildContext context) {
    final planning = context.watch<PlanningState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current group
        Card(
          child: ListTile(
            leading: const Icon(Icons.group, color: Colors.blue),
            title: Text(
              planning.hasGroup
                  ? '${planning.selectedFormation!.name} — ${planning.selectedYear!.name}'
                  : 'Aucun groupe sélectionné',
            ),
            subtitle: planning.hasGroup
                ? Text(planning.selectedGroup!.name)
                : const Text('Appuyez pour choisir votre groupe de TP'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GroupSelectionScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Keywords
        Card(
          child: ListTile(
            leading: const Icon(Icons.filter_alt_outlined, color: Colors.blue),
            title: const Text('Mots-clés à ignorer'),
            subtitle: Text(
              planning.keywords.isEmpty
                  ? 'Aucun mot-clé configuré'
                  : planning.keywords.join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KeywordSettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _notifEnabled,
                  title: const Text('Notifications'),
                  subtitle: Text(
                    '$_notifCount notifications, $_urgentNotifCount urgentes',
                  ),
                  onChanged: _setNotificationsEnabled,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                    await _reloadNotificationSummary();
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Configurer les notifications'),
                ),
              ],
            ),
          ),
        ),
        if (planning.hasGroup) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await planning.clearGroup();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer le groupe'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showClearConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer vos identifiants ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<AppState>().clearCredentials();
      if (!mounted) return;
      setState(() {
        _studentIdController.clear();
        _passwordController.clear();
        _hasExistingCredentials = false;
        _initialStudentId = '';
        _hasUnsavedChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identifiants supprimés'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
