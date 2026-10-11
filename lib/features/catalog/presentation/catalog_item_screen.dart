import 'package:flutter/material.dart';

// STUB — replaced by the feature implementation.
class CatalogItemScreen extends StatelessWidget {
  const CatalogItemScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('CatalogItemScreen')));
}
