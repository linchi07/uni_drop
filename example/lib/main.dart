import 'package:flutter/material.dart';
import 'package:uni_drop/uni_drop.dart';

void main() => runApp(const MaterialApp(home: DropDemo()));

class DropDemo extends StatefulWidget {
  const DropDemo({super.key});
  @override
  State<DropDemo> createState() => _DropDemoState();
}

class _DropDemoState extends State<DropDemo> {
  bool _over = false;
  final _entries = <String>[];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('uni_drop · received items')),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: NativeDropRegion(
            supportedFormats: {const AllowAllFileFormats()},
            onDropEnter: (_) => setState(() => _over = true),
            onDropLeave: (_) {
              if (mounted) {
                setState(() => _over = false);
              }
            },
            onDropError: (failure) {
              if (mounted) {
                setState(() => _entries.add('Error: ${failure.error}'));
              }
            },
            onPerformDrop: (event) async {
              final entries = <String>[];
              for (final item in event.reader.items) {
                final value = item is NativeText
                    ? await item.getText()
                    : item.name ?? item.format.extension;
                entries.add(
                    '${item.runtimeType} · $value · at ${event.localLocation}');
              }
              if (mounted) setState(() => _entries.addAll(entries));
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: _over ? Colors.teal.shade50 : Colors.grey.shade100,
                  border: Border.all(color: _over ? Colors.teal : Colors.grey)),
              child: SizedBox.expand(
                  child: _entries.isEmpty
                      ? const Center(
                          child: Text('Drop text, images or files here'))
                      : ListView(children: [
                          for (final entry in _entries)
                            ListTile(title: Text(entry))
                        ])),
            ),
          ),
        ),
      );
}
