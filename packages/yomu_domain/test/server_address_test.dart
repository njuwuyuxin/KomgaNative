import 'package:yomu_domain/yomu_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ServerAddress.parse', () {
    test('补协议并去掉尾斜杠', () {
      expect(ServerAddress.parse('example.com').baseUrl, 'https://example.com');
      expect(
        ServerAddress.parse('https://example.com/').baseUrl,
        'https://example.com',
      );
      expect(
        ServerAddress.parse('  https://example.com///  ').baseUrl,
        'https://example.com',
      );
      expect(
        ServerAddress.parse('192.168.1.10:25600').baseUrl,
        'https://192.168.1.10:25600',
      );
    });

    test('保留端口与反代子路径', () {
      final a = ServerAddress.parse('http://nas.local:25600/komga/');
      expect(a.baseUrl, 'http://nas.local:25600/komga');
      expect(a.host, 'nas.local');
      expect(a.port, 25600);
      expect(a.isHttps, isFalse);
    });

    test('丢弃查询串与片段（用户从浏览器复制常见）', () {
      expect(
        ServerAddress.parse('https://k.example.com/komga/?tab=1#top').baseUrl,
        'https://k.example.com/komga',
      );
    });

    test('非法输入抛 FormatException，消息可直接展示', () {
      expect(() => ServerAddress.parse(''), throwsA(isA<FormatException>()));
      expect(() => ServerAddress.parse('   '), throwsA(isA<FormatException>()));
      expect(
        () => ServerAddress.parse('ftp://example.com'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ServerAddress.parse('https://'),
        throwsA(isA<FormatException>()),
      );
      // Uri.parse 会把空格编码进 host，必须在解析前挡掉
      expect(
        () => ServerAddress.parse('not a url'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ServerAddress.parse('https://exa mple.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('明文告警只针对公网地址（家用 NAS 内网 http 不该告警）', () {
      // 内网：不告警，否则用户会把告警当噪音忽略掉。
      for (final host in <String>[
        'http://192.168.1.10:25600',
        'http://10.0.2.2:25600',
        'http://172.16.5.4:8080',
        'http://169.254.1.1',
        'http://localhost:25600',
        'http://nas.local:25600',
        'http://[fe80::1]:25600',
        'http://[fd00::1]:25600',
      ]) {
        expect(
          ServerAddress.parse(host).isInsecureRemote,
          isFalse,
          reason: '$host 属于内网/本机，不该告警',
        );
      }

      // 公网明文：必须告警。
      for (final host in <String>[
        'http://komga.example.com',
        'http://8.8.8.8:25600',
        'http://172.32.0.1',
        'http://192.169.0.1',
      ]) {
        expect(
          ServerAddress.parse(host).isInsecureRemote,
          isTrue,
          reason: '$host 是公网明文，应告警',
        );
      }

      // HTTPS 永远不告警（哪怕内网）。
      expect(
        ServerAddress.parse('https://192.168.1.10').isInsecureRemote,
        isFalse,
      );
    });

    test('isPrivateHost 只认标准内网段与家用命名', () {
      expect(ServerAddress.parse('192.168.31.7').isPrivateHost, isTrue);
      expect(ServerAddress.parse('172.15.0.1').isPrivateHost, isFalse);
      expect(ServerAddress.parse('172.31.255.255').isPrivateHost, isTrue);
      expect(ServerAddress.parse('11.0.0.1').isPrivateHost, isFalse);
      expect(ServerAddress.parse('nas.local').isPrivateHost, isTrue);
      expect(ServerAddress.parse('komga.lan').isPrivateHost, isTrue);
      expect(ServerAddress.parse('komga.example.com').isPrivateHost, isFalse);
      expect(ServerAddress.parse('[fc00::1]').isPrivateHost, isTrue);
    });

    test('相等性基于规范化后的 URI', () {
      expect(
        ServerAddress.parse('example.com/'),
        equals(ServerAddress.parse('https://example.com')),
      );
    });

    test('withScheme 只换协议，host/port/path 原样保留', () {
      final http = ServerAddress.parse('http://manga.example.com:4433/komga');
      final https = http.withScheme('https');
      expect(https.baseUrl, 'https://manga.example.com:4433/komga');
      expect(https.port, 4433);
      expect(https.isHttps, isTrue);
      // 反向也成立，且幂等。
      expect(https.withScheme('http'), http);
      expect(http.withScheme('http'), http);
      expect(() => http.withScheme('ftp'), throwsA(isA<FormatException>()));
    });
  });

  group('Account', () {
    test('displayName 用 email，ADMIN 角色识别大小写', () {
      const a = Account(
        id: 'u1',
        email: 'me@example.com',
        roles: <String>['admin'],
      );
      expect(a.displayName, 'me@example.com');
      expect(a.isAdmin, isTrue);
      expect(const Account(id: 'u2', email: 'x@y.z').isAdmin, isFalse);
    });
  });
}
