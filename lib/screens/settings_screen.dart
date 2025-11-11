import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

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
    setState(() {
      if (studentId != null) {
        _studentIdController.text = studentId;
        _initialStudentId = studentId;
        _hasExistingCredentials = true;
      }
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      appBar: AppBar(title: const Text('Paramètres')),
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
                  labelText: 'Identifiant étudiant',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  helperText: 'Votre numéro d\'étudiant',
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
            ],
          ),
        ),
      ),
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
