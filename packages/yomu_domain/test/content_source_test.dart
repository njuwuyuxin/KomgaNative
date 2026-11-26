import 'package:test/test.dart';
import 'package:yomu_domain/yomu_domain.dart';

void main() {
  group('ContentSource 与实体 sourceKey', () {
    test('本机源与远程源能力位与 isCloud 语义准确', () {
      const local = LocalContentSource();
      expect(local.sourceKey, kLocalSourceKey);
      expect(local.isCloud, isFalse);
      expect(local.capabilities.canImportLocalFiles, isTrue);
      expect(local.capabilities.canMutateCatalog, isTrue);
      expect(local.capabilities.canDownloadOffline, isFalse);
      expect(local.capabilities.showsNetworkOfflineBanner, isFalse);
      expect(local.capabilities.supportsCollections, isTrue);
      expect(local.capabilities.syncsProgressRemotely, isFalse);

      const komga = RemoteContentSource(
        sourceKey: 'https://komga.example.com',
        displayName: 'NAS Komga',
      );
      expect(komga.isCloud, isTrue);
      expect(komga.kind, SourceKind.komga);
      expect(komga.capabilities.canImportLocalFiles, isFalse);
      expect(komga.capabilities.canDownloadOffline, isTrue);
      expect(komga.capabilities.syncsProgressRemotely, isTrue);

      const kavita = RemoteContentSource(
        sourceKey: 'kavita|https://kavita.example.com',
        displayName: 'Kavita',
        kind: SourceKind.kavita,
      );
      expect(kavita.isCloud, isTrue);
      expect(kavita.kind, SourceKind.kavita);

      const unknown = SourceCapabilities.none;
      expect(unknown.canImportLocalFiles, isFalse);
      expect(unknown.canMutateCatalog, isFalse);
      expect(unknown.canDownloadOffline, isFalse);
      expect(unknown.showsNetworkOfflineBanner, isFalse);
      expect(unknown.supportsCollections, isFalse);
      expect(unknown.syncsProgressRemotely, isFalse);
    });

    test('Series / Book / Collection / ReadList 默认本机，withSource 切换云端并由 withProgress 保留', () {
      const series = Series(id: 's1', libraryId: 'l1', title: 'Frieren');
      expect(series.sourceKey, kLocalSourceKey);
      expect(series.isCloud, isFalse);

      final cloudSeries = series.withSource('https://komga.example.com');
      expect(cloudSeries.isCloud, isTrue);
      expect(cloudSeries.sourceKey, 'https://komga.example.com');

      final book = const Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        pagesCount: 20,
      ).withSource('https://komga.example.com');
      expect(book.isCloud, isTrue);

      final progressed = book.withProgress(
        ReadProgress(
          page: 5,
          completed: false,
          lastModified: DateTime.utc(2026, 11, 26),
        ),
      );
      expect(progressed.sourceKey, 'https://komga.example.com');
      expect(progressed.isCloud, isTrue);

      final col = const Collection(
        id: 'c1',
        name: 'Top',
        ordered: false,
        seriesIds: <String>['s1'],
      ).withSource('https://komga.example.com');
      expect(col.isCloud, isTrue);

      final rl = const ReadList(
        id: 'rl1',
        name: 'Order',
        summary: '',
        ordered: true,
        bookIds: <String>['b1'],
      ).withSource('https://komga.example.com');
      expect(rl.isCloud, isTrue);
    });
  });
}
