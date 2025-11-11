import 'package:flutter/material.dart';
import '../widgets/warning_message.dart';

class WarningDetailsScreen extends StatelessWidget {
  const WarningDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avertissement Important')),
      body: WarningMessage(
        showAcceptButton: false,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}
