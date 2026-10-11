import 'package:flutter/material.dart';

// STUB — replaced by the feature implementation.
class CardShareScreen extends StatelessWidget {
  const CardShareScreen({super.key, this.cardId, this.staffMode = false});

  final String? cardId;
  final bool staffMode;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('CardShareScreen')));
}
