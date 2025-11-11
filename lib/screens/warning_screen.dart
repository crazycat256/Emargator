import 'package:flutter/material.dart';
import '../widgets/warning_message.dart';

class WarningScreen extends StatelessWidget {
  final VoidCallback onAccept;

  const WarningScreen({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WarningMessage(showAcceptButton: true, onAccept: onAccept),
    );
  }
}
