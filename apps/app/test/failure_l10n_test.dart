import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/l10n/failure_text.dart';

/// I18N-01：失败类型 → 本地化文案。
void main() {
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations.delegate.load(locale);

  test('每种失败都有 zh / en 两套文案，且中文不是英文原样', () async {
    final en = await load(const Locale('en'));
    final zh = await load(const Locale('zh'));

    for (final kind in ShelfFailureKind.values) {
      final enTitle = en.failureTitle(kind);
      final zhTitle = zh.failureTitle(kind);
      expect(enTitle.trim(), isNotEmpty);
      expect(zhTitle.trim(), isNotEmpty);
      expect(zhTitle, isNot(enTitle), reason: '$kind 的中文标题没有翻译');
      // 中文里至少有一个汉字（防止直接 copy 英文）。
      expect(
        RegExp('[\u4e00-\u9fa5]').hasMatch(zhTitle),
        isTrue,
        reason: '$kind 的中文标题不含汉字',
      );
      expect(zh.failureHint(kind).trim(), isNotEmpty);
    }
  });

  test('KomgaError → ShelfFailure 的种类映射完整', () {
    expect(
      shelfFailureOf(const KomgaAuthError('401')).kind,
      ShelfFailureKind.auth,
    );
    expect(
      shelfFailureOf(const KomgaNetworkError('offline')).kind,
      ShelfFailureKind.network,
    );
    expect(
      shelfFailureOf(const KomgaServerError('500', statusCode: 500)).kind,
      ShelfFailureKind.server,
    );
    expect(
      shelfFailureOf(const KomgaProtocolError('bad')).kind,
      ShelfFailureKind.protocol,
    );
    expect(
      shelfFailureOf(const KomgaTlsError('changed')).kind,
      ShelfFailureKind.certificate,
    );
  });

  test('未知错误一律归类为 unexpected，不把原对象拼进界面', () async {
    final zh = await load(const Locale('zh'));

    expect(failureKindOf(StateError('boom')), ShelfFailureKind.unexpected);
    expect(failureKindOf(null), ShelfFailureKind.unexpected);
    expect(
      failureKindOf(const UnexpectedFailure('detail')),
      ShelfFailureKind.unexpected,
    );

    // 文案里不会出现原始异常文本。
    final title = zh.failureTitle(failureKindOf(StateError('boom')));
    expect(title, isNot(contains('boom')));
  });
}
