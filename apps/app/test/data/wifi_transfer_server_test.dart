import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/wifi_transfer_server.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

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
  const gpFlag = 0x0800;

  for (final e in entries.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.key);
    final data = Uint8List.fromList(e.value);
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
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
      ..setUint16(8, gpFlag, Endian.little)
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

void main() {
  group('LMB-07 WifiTransferServer 局域网 HTTP 传书服务', () {
    late Directory sandboxTemp;
    late ProgressDatabase db;
    late WifiTransferServer server;
    late HttpClient client;

    setUp(() {
      sandboxTemp = Directory.systemTemp.createTempSync('yomu_wifi_sandbox_');
      db = ProgressDatabase(NativeDatabase.memory());
      final importer = LocalComicImporter(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );
      server = WifiTransferServer(
        importer: importer,
        lanAddressesResolver: () async => const <String>['127.0.0.1'],
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.dispose();
      await db.close();
      if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
    });

    test('GET / 返回拖拽网页，POST /api/upload 流式导入 CBZ 并在开启 PIN 时严格校验', () async {
      final urls = await server.start(
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
        pin: '4321',
      );
      final base = Uri.parse(urls.single);

      // 1) GET / 返回内置 HTML 页面
      final homeReq = await client.getUrl(base);
      final homeRes = await homeReq.close();
      final html = await utf8.decodeStream(homeRes);
      expect(homeRes.statusCode, HttpStatus.ok);
      expect(html, contains('Yomu · Wi-Fi'));

      final cbz = _buildCbz(<String, List<int>>{
        '01.png': _fakePng(800, 1200),
        '02.png': _fakePng(800, 1200),
      });

      // 2) 未带 PIN 或错 PIN -> 401
      final badReq = await client.postUrl(
        base.resolve('/api/upload?name=Frieren%20Vol.1.cbz'),
      );
      badReq.headers.set('x-yomu-pin', '0000');
      badReq.add(cbz);
      final badRes = await badReq.close();
      await badRes.drain<void>();
      expect(badRes.statusCode, HttpStatus.unauthorized);

      // 3) 正确 PIN -> 200 且入库成功
      final events = <WifiTransferEvent>[];
      final sub = server.events.listen(events.add);
      addTearDown(sub.cancel);

      final okReq = await client.postUrl(
        base.resolve('/api/upload?name=Frieren%20Vol.1.cbz'),
      );
      okReq.headers.set('x-yomu-pin', '4321');
      okReq.add(cbz);
      final okRes = await okReq.close();
      final body =
          jsonDecode(await utf8.decodeStream(okRes)) as Map<String, Object?>;
      expect(okRes.statusCode, HttpStatus.ok);
      expect(body['ok'], isTrue);
      expect(body['importedCount'], 1);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Frieren');
      expect(
        events.any((e) => e.kind == WifiTransferEventKind.imported),
        isTrue,
      );
    });

    test('支持逐图上传后 commit-folder 整文件夹导入为单册漫画', () async {
      final urls = await server.start(
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final base = Uri.parse(urls.single);

      for (final name in const <String>['01.png', '02.png']) {
        final req = await client.postUrl(
          base.resolve('/api/upload-image?folder=Bocchi&name=$name'),
        );
        req.add(_fakePng(800, 1200));
        final res = await req.close();
        await res.drain<void>();
        expect(res.statusCode, HttpStatus.ok);
      }

      final commitReq = await client.postUrl(
        base.resolve('/api/commit-folder?folder=Bocchi'),
      );
      final commitRes = await commitReq.close();
      final json = jsonDecode(
        await utf8.decodeStream(commitRes),
      ) as Map<String, Object?>;
      expect(commitRes.statusCode, HttpStatus.ok);
      expect(json['ok'], isTrue);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Bocchi');
    });
  });
}
