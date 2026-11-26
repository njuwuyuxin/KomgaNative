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

    test('POST /api/upload 返回 seriesIds 且 /api/upload-series-cover 绑定系列封面不产生假书', () async {
      final urls = await server.start(
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
        pin: '9988',
      );
      final base = Uri.parse(urls.single);

      final htmlReq = await client.getUrl(base);
      final htmlRes = await htmlReq.close();
      final html = await utf8.decodeStream(htmlRes);
      expect(html, contains('/api/upload-series-cover'));
      expect(html, contains('SIDECAR_COVER_PRIO'));

      final cbz = _buildCbz(<String, List<int>>{
        '01.png': _fakePng(800, 1200),
        '02.png': _fakePng(800, 1200),
      });
      final upReq = await client.postUrl(
        base.resolve(
          '/api/upload?name=Vol.1.cbz&parent=%E6%BB%85%E9%AC%BC%E4%B9%8B%E5%88%83',
        ),
      );
      upReq.headers.set('x-yomu-pin', '9988');
      upReq.add(cbz);
      final upRes = await upReq.close();
      final upJson =
          jsonDecode(await utf8.decodeStream(upRes)) as Map<String, Object?>;
      expect(upRes.statusCode, HttpStatus.ok);
      final seriesIds = (upJson['seriesIds'] as List<Object?>).cast<String>();
      expect(seriesIds, hasLength(1));

      // 错 PIN 上传封面 -> 401
      final badCoverReq = await client.postUrl(
        base.resolve(
          '/api/upload-series-cover?seriesId=${Uri.encodeComponent(seriesIds.single)}&name=cover.png',
        ),
      );
      badCoverReq.headers.set('x-yomu-pin', '0000');
      badCoverReq.add(_fakePng(600, 900));
      final badCoverRes = await badCoverReq.close();
      await badCoverRes.drain<void>();
      expect(badCoverRes.statusCode, HttpStatus.unauthorized);

      // 正确 PIN 上传 cover.png -> 绑定 customCoverPath 且不新增假书、不增加 receivedCount
      final coverBytes = _fakePng(600, 900);
      final coverReq = await client.postUrl(
        base.resolve(
          '/api/upload-series-cover?seriesId=${Uri.encodeComponent(seriesIds.single)}&name=cover.png',
        ),
      );
      coverReq.headers.set('x-yomu-pin', '9988');
      coverReq.add(coverBytes);
      final coverRes = await coverReq.close();
      final coverJson =
          jsonDecode(await utf8.decodeStream(coverRes)) as Map<String, Object?>;
      expect(coverRes.statusCode, HttpStatus.ok);
      expect(coverJson['ok'], isTrue);
      expect(coverJson['applied'], isTrue);
      expect(server.receivedCount, 1);

      final seriesRow = await db.localSeriesRowById(seriesIds.single);
      expect(seriesRow?.customCoverPath, isNotNull);
      final savedFile = File(
        '${sandboxTemp.path}/${seriesRow!.customCoverPath}',
      );
      expect(savedFile.readAsBytesSync(), coverBytes);

      final books = await db.queryLocalSeriesBooks(seriesIds.single);
      expect(books.items, hasLength(1));

      // 再次上传同名封面不会覆盖已有自定义封面
      final secondCoverReq = await client.postUrl(
        base.resolve(
          '/api/upload-series-cover?seriesId=${Uri.encodeComponent(seriesIds.single)}&name=folder.png',
        ),
      );
      secondCoverReq.headers.set('x-yomu-pin', '9988');
      secondCoverReq.add(_fakePng(400, 600));
      final secondCoverRes = await secondCoverReq.close();
      final secondCoverJson = jsonDecode(
        await utf8.decodeStream(secondCoverRes),
      ) as Map<String, Object?>;
      expect(secondCoverRes.statusCode, HttpStatus.ok);
      expect(secondCoverJson['applied'], isFalse);
      expect(savedFile.readAsBytesSync(), coverBytes);
    });

    test('P2-1 安全加固：拒绝 query string 传 PIN、连续错 PIN 返回 429 锁定并可超时恢复', () async {
      var clock = DateTime.utc(2026, 11, 26, 12);
      final securedServer = WifiTransferServer(
        importer: LocalComicImporter(
          db: db,
          storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
        ),
        lanAddressesResolver: () async => const <String>['127.0.0.1'],
        maxPinFailures: 3,
        pinLockoutDuration: const Duration(seconds: 30),
        now: () => clock,
      );
      addTearDown(securedServer.dispose);

      final urls = await securedServer.start(
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
        pin: '654321',
      );
      final base = Uri.parse(urls.single);

      // 1) 仅通过 URL query ?pin=654321 传递正确 PIN 必须被拒绝（401）
      final qReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=A&name=01.png&pin=654321'),
      );
      qReq.add(_fakePng(100, 100));
      final qRes = await qReq.close();
      await qRes.drain<void>();
      expect(qRes.statusCode, HttpStatus.unauthorized);

      // 2) 第 2 次失败 -> 401；第 3 次失败触发锁定 -> 429
      final bad2 = await client.postUrl(
        base.resolve('/api/upload-image?folder=A&name=01.png'),
      );
      bad2.headers.set('x-yomu-pin', '111111');
      bad2.add(_fakePng(100, 100));
      final bad2Res = await bad2.close();
      await bad2Res.drain<void>();
      expect(bad2Res.statusCode, HttpStatus.unauthorized);

      final bad3 = await client.postUrl(
        base.resolve('/api/upload-image?folder=A&name=01.png'),
      );
      bad3.headers.set('x-yomu-pin', '222222');
      bad3.add(_fakePng(100, 100));
      final bad3Res = await bad3.close();
      await bad3Res.drain<void>();
      expect(bad3Res.statusCode, HttpStatus.tooManyRequests);
      expect(bad3Res.headers.value(HttpHeaders.retryAfterHeader), isNotNull);

      // 3) 锁定期内即使提供正确请求头 PIN 也被 429 拦截
      final lockedReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=A&name=01.png'),
      );
      lockedReq.headers.set('x-yomu-pin', '654321');
      lockedReq.add(_fakePng(100, 100));
      final lockedRes = await lockedReq.close();
      await lockedRes.drain<void>();
      expect(lockedRes.statusCode, HttpStatus.tooManyRequests);

      // 4) 锁定过期后，正确请求头 PIN 恢复通过
      clock = clock.add(const Duration(seconds: 31));
      final okReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=A&name=01.png'),
      );
      okReq.headers.set('x-yomu-pin', '654321');
      okReq.add(_fakePng(100, 100));
      final okRes = await okReq.close();
      await okRes.drain<void>();
      expect(okRes.statusCode, HttpStatus.ok);
    });

    test('P2-1 安全加固：单文件与整次会话超体积上限返回 413 并不落盘', () async {
      final limitedServer = WifiTransferServer(
        importer: LocalComicImporter(
          db: db,
          storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
        ),
        lanAddressesResolver: () async => const <String>['127.0.0.1'],
        maxImageBytes: 64,
        maxArchiveBytes: 64,
        maxSessionBytes: 80,
      );
      addTearDown(limitedServer.dispose);

      final urls = await limitedServer.start(
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final base = Uri.parse(urls.single);

      // 1) 单张图片超过 64 字节 -> 413
      final bigImgReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=Cap&name=big.png'),
      );
      bigImgReq.add(Uint8List(100));
      final bigImgRes = await bigImgReq.close();
      await bigImgRes.drain<void>();
      expect(bigImgRes.statusCode, HttpStatus.requestEntityTooLarge);

      // 2) 第一张 50 字节成功；第二张 50 字节累计超过会话 80 字节上限 -> 413
      final okReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=Cap&name=01.png'),
      );
      okReq.add(Uint8List(50));
      final okRes = await okReq.close();
      await okRes.drain<void>();
      expect(okRes.statusCode, HttpStatus.ok);

      final overSessionReq = await client.postUrl(
        base.resolve('/api/upload-image?folder=Cap&name=02.png'),
      );
      overSessionReq.add(Uint8List(50));
      final overSessionRes = await overSessionReq.close();
      await overSessionRes.drain<void>();
      expect(overSessionRes.statusCode, HttpStatus.requestEntityTooLarge);
    });
  });
}
