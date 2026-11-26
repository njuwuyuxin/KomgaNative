import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/archive_password_provider.dart';
import 'package:yomu/src/widgets/archive_password_dialog.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

void main() {
  testWidgets('LMB-13 showArchivePasswordDialog 显示错误提示、切换明文并返回密码与词典勾选项', (
    WidgetTester tester,
  ) async {
    ArchivePasswordSubmission? submitted;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                submitted = await showArchivePasswordDialog(
                  context,
                  fileName: 'Secret.cbz',
                  wrongAttempt: true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('archive-password-field')),
      'manga999',
    );
    await tester.tap(find.byKey(const Key('archive-password-visibility')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-password-submit')));
    await tester.pumpAndSettle();

    expect(submitted?.password, 'manga999');
    expect(submitted?.saveToDictionary, isTrue);
  });

  testWidgets('LMB-13 showPasswordDictionarySheet 支持添加与删除常用解压密码', (
    WidgetTester tester,
  ) async {
    final store = ArchivePasswordStore.inMemory();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          archivePasswordStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => showPasswordDictionarySheet(context),
                child: const Text('Dict'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Dict'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pwd-dict-input')), 'kmoe2026');
    await tester.tap(find.byKey(const Key('pwd-dict-add')));
    await tester.pumpAndSettle();
    expect(find.text('kmoe2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pwd-dict-delete-0')));
    await tester.pumpAndSettle();
    expect(find.text('kmoe2026'), findsNothing);
    expect(await store.loadCommonPasswords(), isEmpty);
  });
}
