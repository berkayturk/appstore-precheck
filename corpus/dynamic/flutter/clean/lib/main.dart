import 'package:flutter/material.dart';

void main() => runApp(const PrecheckApp());

class PrecheckApp extends StatefulWidget {
  const PrecheckApp({super.key});

  @override
  State<PrecheckApp> createState() => _PrecheckAppState();
}

class _PrecheckAppState extends State<PrecheckApp> {
  String status = 'Ready';

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Precheck Flutter Clean')),
          body: ListView(children: [
            TextButton(
                onPressed: () => setState(() => status = 'Account deleted'),
                child: const Text('Delete Account')),
            TextButton(
                onPressed: () => setState(() => status = 'Restore request completed'),
                child: const Text('Restore Purchases')),
            TextButton(
                onPressed: () => setState(() => status = 'Report submitted'),
                child: const Text('Report Content')),
            Text(status),
          ]),
        ),
      );
}
