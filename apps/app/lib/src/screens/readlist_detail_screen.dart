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
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.pop(),
                ),
                title: Text(title ?? l10n.readListFallback),
              ),
            ),
            Builder(
              builder: (BuildContext context) {
                if (async.hasError && !async.hasValue) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatusView(
                      icon: Icons.cloud_off_outlined,
                      title: async.error is ShelfFailure
                          ? (async.error! as ShelfFailure).message
                          : l10n.errorGeneric,
                      actionLabel: l10n.retry,
                      onAction: () =>
                          ref.invalidate(readListBooksProvider(readListId)),
                    ),
                  );
                }
                final page = async.value;
                if (page == null) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (page.items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatusView(
                      icon: Icons.list_alt_outlined,
                      title: l10n.readListsEmpty,
                    ),
                  );
                }
                return SliverList.list(
                  key: const Key('readlist-books-list'),
                  children: <Widget>[
                    for (final book in page.items)
                      SeriesBookRow(
                        book: book,
                        onOpen: () async {
                          await context.push(
                            '/reader/${book.id}',
                            extra: ReaderArgs(book: book),
                          );
                          ref.invalidate(readListBooksProvider(readListId));
                        },
                      ),
                  ],
                );
              },
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSizes.navBarClearance),
            ),
          ],
        ),
      ),
    );
  }
}
