import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/widgets/series_book_row.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读列表里的书（UI-P3-8）。
class ReadListDetailScreen extends ConsumerWidget {
  const ReadListDetailScreen({required this.readListId, this.title, super.key});

  final String readListId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readListBooksProvider(readListId));
    return Scaffold(
      appBar: AppBar(title: Text(title ?? l10n.readListFallback)),
      body: Builder(
        builder: (BuildContext context) {
          if (async.hasError && !async.hasValue) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    async.error is ShelfFailure
                        ? (async.error! as ShelfFailure).message
                        : l10n.errorGeneric,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(readListBooksProvider(readListId)),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }
          final page = async.value;
          if (page == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (page.items.isEmpty) {
            return Center(child: Text(l10n.readListsEmpty));
          }
          return ListView.separated(
            key: const Key('readlist-books-list'),
            itemCount: page.items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: AppSizes.hairline),
            itemBuilder: (BuildContext context, int index) {
              final book = page.items[index];
              return SeriesBookRow(
                book: book,
                onOpen: () async {
                  await context.push(
                    '/reader/${book.id}',
                    extra: ReaderArgs(book: book),
                  );
                  ref.invalidate(readListBooksProvider(readListId));
                },
              );
            },
          );
        },
      ),
    );
  }
}
