import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;
import 'package:super_native_extensions/raw_drag_drop.dart' as drop;

class FakeProgress implements raw.ReadProgress {
  int cancellations = 0;
  @override
  final cancellable = ValueNotifier(true);
  @override
  final fraction = ValueNotifier<double?>(null);
  @override
  void cancel() {
    cancellations++;
  }
}

class FakeItem implements raw.DataReaderItem {
  FakeItem([this.values = const {}]);
  final Map<String, Object?> values;
  final requested = <String>[];
  final progresses = <FakeProgress>[];
  @override
  (Future<Object?>, raw.ReadProgress) getDataForFormat(String format) {
    requested.add(format);
    final progress = FakeProgress();
    progresses.add(progress);
    return (Future<Object?>.value(values[format]), progress);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInfo implements raw.DataReaderItemInfo {
  FakeInfo(
      {this.formats = const [],
      this.synthesizedFormats = const [],
      this.virtualReceivers = const [],
      this.suggestedName,
      this.synthesizedFromURIFormat,
      FakeItem? item})
      : item = item ?? FakeItem();
  @override
  final FakeItem item;
  @override
  final List<String> formats;
  @override
  final List<String> synthesizedFormats;
  @override
  final List<raw.VirtualFileReceiver> virtualReceivers;
  @override
  final String? suggestedName;
  @override
  final String? synthesizedFromURIFormat;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVirtualFile extends raw.VirtualFile {
  FakeVirtualFile(this.chunks, {this.error});
  final List<List<int>> chunks;
  final Object? error;
  int closes = 0;
  @override
  String? get fileName => 'file.bin';
  @override
  int? get length => null;
  @override
  Future<Uint8List> readNext() async {
    if (error != null) throw error!;
    return Uint8List.fromList(chunks.isEmpty ? [] : chunks.removeAt(0));
  }

  @override
  void close() {
    closes++;
  }
}

class FakeReceiver implements raw.VirtualFileReceiver {
  FakeReceiver(this.format, this.pending);
  @override
  final String format;
  final Future<raw.VirtualFile> pending;
  final progress = FakeProgress();
  int requests = 0;
  @override
  (Future<raw.VirtualFile>, raw.ReadProgress) receiveVirtualFile() {
    requests++;
    return (pending, progress);
  }

  @override
  (Future<String>, raw.ReadProgress) copyVirtualFile(
          {required String targetFolder}) =>
      throw UnimplementedError();
}

class FakeContext extends drop.DropContext {
  final registrations = <List<String>>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> registerDropFormats(List<String> formats) async {
    registrations.add(List.of(formats));
  }
}
