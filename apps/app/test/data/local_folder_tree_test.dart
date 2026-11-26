import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_folder_tree.dart';
import 'package:yomu_domain/yomu_domain.dart';

Book _book(String id, String name, {double numberSort = 0}) => Book(
  id: id,
  seriesId: 's1',
  seriesTitle: 'Series',
  name: name,
  number: numberSort == 0 ? '' : '${numberSort.toInt()}',
  pagesCount: 20,
  mediaProfile: MediaProfile.divina,
  sourceKey: kLocalSourceKey,
);

void main() {
  group('LMB-10 buildLocalFolderTree & resolveFolderNode', () {
    test('按多级目录结构自然排序聚合外部挂载书与受管导入书并递归统计册数', () {
      final items = <LocalFolderBookItem>[
        LocalFolderBookItem(
          book: _book('b10', 'Vol.10', numberSort: 10),
          direction: ReadingDirection.rightToLeft,
          numberSort: 10,
          folderSegments: folderSegmentsForLocalBook(
            mountRootId: 'r1',
            sourceRelativePath: 'Shonen/Frieren/Vol.10.cbz',
            mountRootDisplayName: 'SD Comics',
            seriesTitle: 'Frieren',
            importedGroupLabel: 'Imported',
          ),
        ),
        LocalFolderBookItem(
          book: _book('b2', 'Vol.2', numberSort: 2),
          direction: ReadingDirection.rightToLeft,
          numberSort: 2,
          folderSegments: folderSegmentsForLocalBook(
            mountRootId: 'r1',
            sourceRelativePath: 'Shonen/Frieren/Vol.2.cbz',
            mountRootDisplayName: 'SD Comics',
            seriesTitle: 'Frieren',
            importedGroupLabel: 'Imported',
          ),
        ),
        LocalFolderBookItem(
          book: _book('b_imp', 'Bocchi Vol.1', numberSort: 1),
          direction: ReadingDirection.rightToLeft,
          folderSegments: folderSegmentsForLocalBook(
            mountRootId: null,
            sourceRelativePath: null,
            mountRootDisplayName: null,
            seriesTitle: 'Bocchi',
            importedGroupLabel: 'Imported',
          ),
        ),
      ];

      final root = buildLocalFolderTree(items);
      expect(root.totalBooksCount, 3);
      expect(root.subfolders.map((n) => n.name), <String>[
        'Imported',
        'SD Comics',
      ]);

      final sd = resolveFolderNode(root, const <String>['SD Comics']);
      expect(sd.node.totalBooksCount, 2);
      expect(sd.node.subfolders.single.name, 'Shonen');

      final frieren = resolveFolderNode(root, const <String>[
        'SD Comics',
        'Shonen',
        'Frieren',
      ]);
      expect(frieren.resolvedPath, <String>['SD Comics', 'Shonen', 'Frieren']);
      expect(frieren.node.books.map((b) => b.book.id), <String>['b2', 'b10']);

      // 失效面包屑安全回退到最深有效祖先
      final stale = resolveFolderNode(root, const <String>[
        'SD Comics',
        'RemovedFolder',
      ]);
      expect(stale.resolvedPath, <String>['SD Comics']);
      expect(stale.node.name, 'SD Comics');
    });
  });
}
