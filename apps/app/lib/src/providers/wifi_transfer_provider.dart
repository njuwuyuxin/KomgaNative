import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/local/wifi_transfer_server.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';

export 'package:yomu/src/data/local/wifi_transfer_server.dart';

/// Wi-Fi 传书状态快照。
final class WifiTransferState {
  const WifiTransferState({
    this.running = false,
    this.starting = false,
    this.urls = const <String>[],
    this.pinEnabled = false,
    this.pin = '',
    this.receivedCount = 0,
    this.activeFileName,
    this.logs = const <WifiTransferEvent>[],
    this.error,
  });

  final bool running;
  final bool starting;
  final List<String> urls;
  final bool pinEnabled;
  final String pin;
  final int receivedCount;
  final String? activeFileName;
  final List<WifiTransferEvent> logs;
  final String? error;

  WifiTransferState copyWith({
    bool? running,
    bool? starting,
    List<String>? urls,
    bool? pinEnabled,
    String? pin,
    int? receivedCount,
    String? activeFileName,
    bool clearActiveFile = false,
    List<WifiTransferEvent>? logs,
    String? error,
    bool clearError = false,
  }) => WifiTransferState(
    running: running ?? this.running,
    starting: starting ?? this.starting,
    urls: urls ?? this.urls,
    pinEnabled: pinEnabled ?? this.pinEnabled,
    pin: pin ?? this.pin,
    receivedCount: receivedCount ?? this.receivedCount,
    activeFileName: clearActiveFile
        ? null
        : (activeFileName ?? this.activeFileName),
    logs: logs ?? this.logs,
    error: clearError ? null : (error ?? this.error),
  );
}

final Provider<WifiTransferServer> wifiTransferServerProvider =
    Provider<WifiTransferServer>((Ref ref) {
      final server = WifiTransferServer(
        importer: ref.watch(localComicImporterProvider),
      );
      ref.onDispose(() => unawaited(server.dispose()));
      return server;
    });

/// 局域网 Wi-Fi 传书状态控制器（LMB-07）。
class WifiTransferController extends Notifier<WifiTransferState> {
  StreamSubscription<WifiTransferEvent>? _sub;
  final Random _rng = Random();

  @override
  WifiTransferState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
    });
    return WifiTransferState(pin: _generatePin());
  }

  String _generatePin() => (1000 + _rng.nextInt(9000)).toString();

  Future<void> start() async {
    if (state.running || state.starting) return;
    state = state.copyWith(starting: true, clearError: true);
    final server = ref.read(wifiTransferServerProvider);
    try {
      await _sub?.cancel();
      _sub = server.events.listen(_onEvent);
      final urls = await server.start(pin: state.pinEnabled ? state.pin : null);
      if (!ref.mounted) return;
      state = state.copyWith(running: true, starting: false, urls: urls);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        running: false,
        starting: false,
        error: e.toString(),
      );
    }
  }

  Future<void> stop() async {
    final server = ref.read(wifiTransferServerProvider);
    await _sub?.cancel();
    _sub = null;
    if (ref.mounted) {
      state = state.copyWith(
        running: false,
        starting: false,
        urls: const <String>[],
        clearActiveFile: true,
      );
    }
    await server.stop();
  }

  void setPinEnabled(bool enabled) {
    final nextPin = state.pin.isEmpty ? _generatePin() : state.pin;
    state = state.copyWith(pinEnabled: enabled, pin: nextPin);
    ref.read(wifiTransferServerProvider).setPin(enabled ? nextPin : null);
  }

  void regeneratePin() {
    final nextPin = _generatePin();
    state = state.copyWith(pin: nextPin);
    if (state.pinEnabled) {
      ref.read(wifiTransferServerProvider).setPin(nextPin);
    }
  }

  void _onEvent(WifiTransferEvent event) {
    if (!ref.mounted) return;
    switch (event.kind) {
      case WifiTransferEventKind.receiving:
        state = state.copyWith(activeFileName: event.fileName);
      case WifiTransferEventKind.imported:
        final nextLogs = <WifiTransferEvent>[event, ...state.logs.take(19)];
        state = state.copyWith(
          receivedCount: state.receivedCount + event.importedCount,
          clearActiveFile: true,
          logs: nextLogs,
        );
        _refreshLocalShelf();
      case WifiTransferEventKind.failed:
        final nextLogs = <WifiTransferEvent>[event, ...state.logs.take(19)];
        state = state.copyWith(clearActiveFile: true, logs: nextLogs);
    }
  }

  void _refreshLocalShelf() {
    ref.read(localLibraryRepositoryProvider).evictCoverCache();
    ref.invalidate(crossSourceOndeckProvider);
    ref.invalidate(recentSeriesProvider);
    if (!ref.read(activeSourceProvider).isCloud) {
      unawaited(ref.read(shelfProvider.notifier).refreshInPlace());
    }
  }
}

final NotifierProvider<WifiTransferController, WifiTransferState>
wifiTransferProvider =
    NotifierProvider<WifiTransferController, WifiTransferState>(
      WifiTransferController.new,
    );
