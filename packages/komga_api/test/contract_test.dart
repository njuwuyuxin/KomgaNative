import 'dart:convert';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// 对着 Komga 官方 OpenAPI 契约校验本客户端**实际会构造出的每一个 URL**。
///
/// 解决的问题：客户端里"我以为 Komga 长这样"的假设会随时间漂移，而假实现（fake）
/// 永远点头——假实现只证明"我调用了我以为的方法"，不证明这个方法是真实的。
/// 这里把假设钉在官方契约上：fixture 取自 gotson/komga 仓库的
/// `komga/docs/openapi.json`（1.30.1 tag），路径或查询参数写错就直接红。
Map<String, Object?> _loadSpec() =>
    jsonDecode(fixture('openapi-1.30.1.json')) as Map<String, Object?>;

/// 把 `/api/v1/series/{seriesId}/books` 变成正则，用来反查模板。
RegExp _templateToRegExp(String template) =>
    RegExp('^${template.replaceAll(RegExp(r'\{[^}]+\}'), '[^/]+')}\$');

const List<String> _methods = <String>['get', 'post', 'put', 'patch', 'delete'];

class _Call {
  const _Call(this.method, this.url);

  final String method;
  final String url;

  @override
  String toString() =>
      '${method.toUpperCase()} ${Uri.parse(url).path}'
      '${Uri.parse(url).hasQuery ? '?${Uri.parse(url).query}' : ''}';
}

List<_Call> _calls() {
  final urls = KomgaUrls('https://komga.example.com');
  return <_Call>[
    _Call('get', urls.libraries()),
    _Call('get', urls.me()),
    _Call('get', urls.series()),
    _Call('get', urls.series(libraryId: 'L1', search: 'abc')),
    _Call(
      'get',
      urls.series(
        sort: SeriesSort.titleAsc,
        readStatus: SeriesReadStatus.unread,
      ),
    ),
    _Call('get', urls.series(readStatus: SeriesReadStatus.inProgress)),
    _Call('get', urls.seriesBooks('S1')),
    _Call('get', urls.seriesById('S1')),
    _Call('get', urls.collections()),
    _Call('get', urls.collectionSeries('C1')),
    _Call('get', urls.readLists()),
    _Call('get', urls.readListBooks('R1')),
    _Call('get', urls.book('B1')),
    _Call('get', urls.books(search: 'akira')),
    _Call('get', urls.bookPages('B1')),
    _Call('get', urls.pageImage('B1', 1)),
    _Call('get', urls.pageImage('B1', 1, convertToJpeg: true)),
    _Call('get', urls.bookThumbnail('B1')),
    _Call('get', urls.seriesThumbnail('S1')),
    _Call('patch', urls.bookReadProgress('B1')),
    _Call('delete', urls.bookReadProgress('B1')),
    _Call('post', urls.seriesReadProgress('S1')),
    _Call('delete', urls.seriesReadProgress('S1')),
    _Call('get', urls.ondeck()),
    _Call('get', urls.apiKeys()),
    _Call('post', urls.apiKeys()),
  ];
}

Set<String> _declaredQueryParams(Map<String, Object?> operation) {
  final params = operation['parameters'];
  if (params is! List<Object?>) return const <String>{};
  return params
      .whereType<Map<String, Object?>>()
      .where((Map<String, Object?> p) => p['in'] == 'query')
      .map((Map<String, Object?> p) => p['name'])
      .whereType<String>()
      .toSet();
}

void main() {
  final spec = _loadSpec();
  final paths = spec['paths']! as Map<String, Object?>;

  group('OpenAPI 契约（fixture = 官方 1.30.1）', () {
    test('fixture 是 Komga 1.30.1 的规格', () {
      final info = spec['info']! as Map<String, Object?>;
      expect(info['version'], '1.30.1');
      expect(spec['openapi'], startsWith('3.'));
      expect(paths, isNotEmpty);
    });

    for (final call in _calls()) {
      test('$call 在官方契约中声明', () {
        final uri = Uri.parse(call.url);
        String? matched;
        for (final template in paths.keys) {
          if (_templateToRegExp(template).hasMatch(uri.path)) {
            matched = template;
            break;
          }
        }
        expect(matched, isNotNull, reason: '${uri.path} 不在 OpenAPI 里');
        final template = matched;
        if (template == null) return;

        final item = paths[template]! as Map<String, Object?>;
        expect(
          item.keys.where(_methods.contains),
          contains(call.method),
          reason: '$matched 没有声明 ${call.method}',
        );

        final declared = _declaredQueryParams(
          item[call.method]! as Map<String, Object?>,
        );
        for (final key in uri.queryParametersAll.keys) {
          expect(
            declared,
            contains(key),
            reason: '$matched 的 ${call.method} 没有 $key 这个查询参数',
          );
        }

        // 段数必须一致，避免"模板碰巧匹配到另一个端点"
        expect(
          uri.pathSegments.length,
          template.split('/').where((String s) => s.isNotEmpty).length,
          reason: '$template 与 $uri 段数不一致',
        );
      });
    }

    /// 排序的 wire 值（UI-P2-7 的契约面）。
    ///
    /// OpenAPI 只规定 `sort` 的**格式**是 `property(,asc|desc)`，没有列出可排序
    /// 属性清单；而且排序属性是**查询/实体层**的名字，不是 DTO 字段名
    /// （实测过的 `createdDate` 就对应 DTO 里的 `created`），所以没法用
    /// `SeriesDto` 反查。这里只钉格式：每个排序都能解析成 `属性[,方向]`，
    /// 方向只有 asc / desc。属性名本身要靠 `docs/series-queries.md` 的实测清单。
    test('排序 wire 值符合 property,asc|desc 格式', () {
      expect(SeriesSort.values, isNotEmpty);
      for (final sort in SeriesSort.values) {
        final wire = sortWireValue(sort);
        final parts = wire.split(',');
        expect(parts.length, lessThanOrEqualTo(2), reason: '$wire 格式不对');
        expect(parts.first, isNotEmpty, reason: '$wire 没有属性名');
        expect(parts.first.contains(' '), isFalse, reason: '$wire 的属性名里不该有空格');
        expect(
          parts.last,
          anyOf('asc', 'desc'),
          reason: '$wire 的方向只能是 asc / desc',
        );
      }
    });
  });
}
