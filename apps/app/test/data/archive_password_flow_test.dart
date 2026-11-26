import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Uint8List _fakePng(int width, int height, int tag) {
  final b = ByteData(32)
    ..setUint32(16, width)
    ..setUint32(20, height)
    ..setUint8(24, tag);
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

Uint8List _buildEncryptedCbz({
  required Map<String, Uint8List> files,
  required Uint8List passwordBytes,
}) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  const gpFlag = 0x0801;

  for (final e in files.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.key);
    final crc = computeCrc32(e.value);
    final cipher = encryptZipCryptoPayload(
      e.value,
      passwordBytes: passwordBytes,
      checkByte: (crc >> 24) & 0xFF,
    );
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, cipher.length, Endian.little)
      ..setUint32(22, e.value.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(cipher);

    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, cipher.length, Endian.little)
      ..setUint32(24, e.value.length, Endian.little)
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
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  group('LMB-13 加密归档解锁、常用密码词典静默命中与钥匙串持久化', () {
    test('交互弹窗输错 1 次后输对中文 GBK 密码成功解锁，写入词典后第二本同密码零弹窗静默解锁', () async {
      final srcTemp = Directory.systemTemp.createTempSync('yomu_pwd_src_');
      final sbTemp = Directory.systemTemp.createTempSync('yomu_pwd_sb_');
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
        if (sbTemp.existsSync()) sbTemp.deleteSync(recursive: true);
      });

      final passwordStore = ArchivePasswordStore.inMemory();
      final storage = LocalComicsStorage(rootResolver: () async => sbTemp);
      final importer = LocalComicImporter(
        db: db,
        storage: storage,
        passwordStore: passwordStore,
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );

      final p1 = _fakePng(800, 1200, 77);
      final gbkPwd = encodeGbkBytes('迷宫饭')!;
      final vol1File = File('${srcTemp.path}/Vol1.cbz')
        ..writeAsBytesSync(
          _buildEncryptedCbz(
            files: <String, Uint8List>{'01.png': p1},
            passwordBytes: gbkPwd,
          ),
        );

      var prompts = 0;
      final wrongFlags = <bool>[];
      final res1 = await importer.importArchiveFiles(
        <PickedComicFile>[PickedComicFile.fromFile(vol1File, name: 'Vol1.cbz')],
        onPasswordPrompt: (String name, {bool wrongAttempt = false}) async {
          prompts++;
          wrongFlags.add(wrongAttempt);
          if (prompts == 1) {
            return (password: 'wrong_pwd', saveToDictionary: true);
          }
          return (password: '迷宫饭', saveToDictionary: true);
        },
      );

      expect(res1.importedCount, 1);
      expect(prompts, 2);
      expect(wrongFlags, <bool>[false, true]);
      expect(await passwordStore.loadCommonPasswords(), <String>['迷宫饭']);

      // 读页时自动从钥匙串取出该书密码解密，无需再询问用户
      final bookId = res1.importedBookIds.single;
      final readerRepo = LocalReaderRepository(
        db,
        storage,
        passwordStore: passwordStore,
      );
      addTearDown(readerRepo.dispose);
      final readBack = await readerRepo.pageImage(bookId, 1);
      expect(readBack[24], 77);

      // 第二本使用相同中文密码：词典直接静音命中，prompts 不增长
      final vol2File = File('${srcTemp.path}/Vol2.cbz')
        ..writeAsBytesSync(
          _buildEncryptedCbz(
            files: <String, Uint8List>{'01.png': _fakePng(800, 1200, 88)},
            passwordBytes: gbkPwd,
          ),
        );
      var secondPrompts = 0;
      final res2 = await importer.importArchiveFiles(
        <PickedComicFile>[PickedComicFile.fromFile(vol2File, name: 'Vol2.cbz')],
        onPasswordPrompt: (String name, {bool wrongAttempt = false}) async {
          secondPrompts++;
          return null;
        },
      );
      expect(res2.importedCount, 1);
      expect(secondPrompts, 0);
    });
  });
}
