import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/local_library_center_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/local_library_center_screen.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';

Uint8List _fakePng(int width, int height) {
  final b = ByteData(32)
    ..setUint32(16, width)
    ..setUint32(20, height);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(0, 8, const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  bytes.setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52]);
  return bytes;
}

Uint8List _buildCbz(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  for (final e in entries.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.key);
    final data = Uint8List.fromList(e.value);
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);
    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cdfh.buffer.asUint8List())
      ..add(nameBytes);
  }
  final cdOffset = out.length;
  final cdBytes = cd.takeBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

final class _FakeMountBridge extends ChannelExternalRootsBridge {
  _FakeMountBridge(this._dirToPick);
  final Directory _dirToPick;

  @override
  Future<MountedExternalRoot?> pickDirectory() async => MountedExternalRoot(
    id: 'root_picked',
    displayName: 'SD Manga',
    uriOrBookmark: _dirToPick.path,
    kind: ExternalRootKind.localDirectory,
  );
}

void main() {
  testWidgets('LMB-09 LocalLibraryCenterScreen 挂载外部目录、展示扫描结果与安全卸载', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 2, 920 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final extDir = Directory.systemTemp.createTempSync('yomu_center_ext_');
    final sandboxDir = Directory.systemTemp.createTempSync('yomu_center_sb_');
    final cbzFile = File('${extDir.path}/Vol.1.cbz')
      ..writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );
    final db = ProgressDatabase(NativeDatabase.memory());
    final storage = LocalComicsStorage(rootResolver: () async => sandboxDir);
    final bridge = _FakeMountBridge(extDir);

    addTearDown(() async {
      await db.close();
      if (extDir.existsSync()) extDir.deleteSync(recursive: true);
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(storage),
          externalRootsBridgeProvider.overrideWithValue(bridge),
          externalDirectoryScannerProvider.overrideWithValue(
            ExternalDirectoryScanner(
              db: db,
              storage: storage,
              bridge: bridge,
              coverEncoder: (
                Uint8List raw, {
                required ReadingDirection direction,
              }) async => raw,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const LocalLibraryCenterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-center-roots-empty')), findsOneWidget);

    // 1) 点击挂载外部目录 -> 自动创建 .nomedia、增量扫描并显示结果横幅
    await tester.tap(find.byKey(const Key('local-center-mount-root')));
    final scanDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (find
            .byKey(const Key('local-center-scan-summary'))
            .evaluate()
            .isEmpty &&
        DateTime.now().isBefore(scanDeadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(File('${extDir.path}/.nomedia').existsSync(), isTrue);
    expect(find.byKey(const Key('local-center-scan-summary')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('mounted-root-root_picked')),
      200,
    );
    expect(find.byKey(const Key('mounted-root-root_picked')), findsOneWidget);

    // 2) 点击卸载并确认 -> 移除索引但外部原始文件完好无损
    await tester.tap(find.byKey(const Key('root-unmount-root_picked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-unmount-root')));
    final unmountDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (find
            .byKey(const Key('mounted-root-root_picked'))
            .evaluate()
            .isNotEmpty &&
        DateTime.now().isBefore(unmountDeadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-center-roots-empty')), findsOneWidget);
    expect(cbzFile.existsSync(), isTrue);
  });
}
