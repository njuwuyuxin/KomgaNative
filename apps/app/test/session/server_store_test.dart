import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/server_store.dart';

import '../support/fakes.dart';

/// 指纹是 TOFU 的全部保障：存错、存脏、读丢失都会让 TLS 校验悄悄降级，
/// 所以持久化格式单独钉住。
void main() {
  group('StoredServer 的证书指纹', () {
    test('没有指纹 → 严格校验（默认）', () {
      final server = storedServer();
      expect(server.certificateFingerprint, isNull);
      expect(server.tls.isStrict, isTrue);
    });

    test('有指纹 → 只放行这一张证书', () {
      final fingerprint = expiredCertificate().derSha256;
      final server = storedServer().copyWith(
        certificateFingerprint: fingerprint,
      );
      expect(server.tls.pinnedSha256, fingerprint);
      expect(server.tls.isStrict, isFalse);
    });

    test('JSON 往返保留指纹', () {
      final fingerprint = expiredCertificate().derSha256;
      final original = storedServer().copyWith(
        certificateFingerprint: fingerprint,
      );
      final restored = StoredServer.fromJson(original.toJson());
      expect(restored.certificateFingerprint, fingerprint);
      expect(restored.address, original.address);
      expect(restored.apiKey, original.apiKey);
    });

    test('指纹非法（长度/字符不对）→ 当作没信任过，不降级校验', () {
      for (final bad in <Object?>['abc', 'zz' * 32, 42]) {
        final json = <String, Object?>{
          ...storedServer().toJson(),
          'certificateFingerprint': bad,
        };
        final restored = StoredServer.fromJson(json);
        expect(
          restored.certificateFingerprint,
          isNull,
          reason: '脏指纹 $bad 不能被当成信任凭据',
        );
        expect(restored.tls.isStrict, isTrue);
      }
    });

    test('旧版本存档（没有该字段）照常读取', () {
      final json = storedServer().toJson()..remove('certificateFingerprint');
      final restored = StoredServer.fromJson(json);
      expect(restored.accountEmail, 'me@example.com');
      expect(restored.tls.isStrict, isTrue);
    });
  });

  group('多服务器存储语义', () {
    StoredServer other() => StoredServer(
      address: ServerAddress.parse('https://other.example.com'),
      apiKey: 'other-key',
      accountEmail: 'other@example.com',
    );

    test('save 会加入列表并设为活动；同地址覆盖不产生第二条', () async {
      final store = InMemoryServerStore();
      final first = storedServer();
      await store.save(first);
      await store.save(other());
      await store.save(first);

      final all = await store.all();
      expect(all, hasLength(2));
      expect((await store.load())?.id, first.id);
    });

    test('remove 删掉指定服务器；删活动服务器后 load 为 null', () async {
      final first = storedServer();
      final second = other();
      final store = InMemoryServerStore.withAll(<StoredServer>[
        first,
        second,
      ], active: first);

      await store.remove(second);
      expect(await store.all(), hasLength(1));
      expect((await store.load())?.id, first.id);

      await store.remove(first);
      expect(await store.load(), isNull);
      expect(await store.all(), isEmpty);
    });

    test('clear 只清活动标记，不忘掉列表（Disconnect ≠ 删除所有服务器）', () async {
      final first = storedServer();
      final second = other();
      final store = InMemoryServerStore.withAll(<StoredServer>[
        first,
        second,
      ], active: first);

      await store.clear();

      expect(await store.load(), isNull);
      expect(await store.all(), hasLength(2));
    });
  });
}
