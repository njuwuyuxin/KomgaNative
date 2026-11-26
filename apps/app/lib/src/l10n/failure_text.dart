import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';

/// 把数据层的失败类型翻译成本地化文案（I18N-01）。
///
/// 数据层只带 `kind`，文案全部在 ARB 里：切到中文时连接失败/书架失败
/// 会跟着变成中文，而不是把数据层写死的英文句子直接甩给用户。
extension ShelfFailureText on AppLocalizations {
  String failureTitle(ShelfFailureKind kind) => switch (kind) {
    ShelfFailureKind.auth => failureAuthTitle,
    ShelfFailureKind.network => failureNetworkTitle,
    ShelfFailureKind.server => failureServerTitle,
    ShelfFailureKind.protocol => failureProtocolTitle,
    ShelfFailureKind.notFound => failureNotFoundTitle,
    ShelfFailureKind.certificate => failureCertificateTitle,
    ShelfFailureKind.unexpected => failureUnexpectedTitle,
  };

  String failureHint(ShelfFailureKind kind) => switch (kind) {
    ShelfFailureKind.auth => failureAuthHint,
    ShelfFailureKind.network => failureNetworkHint,
    ShelfFailureKind.server => failureServerHint,
    ShelfFailureKind.protocol => failureProtocolHint,
    ShelfFailureKind.notFound => failureNotFoundHint,
    ShelfFailureKind.certificate => failureCertificateHint,
    ShelfFailureKind.unexpected => failureUnexpectedHint,
  };
}

/// 任意错误 → 种类。**未知类型一律 `unexpected`**，绝不把 `Object` 拼进界面。
ShelfFailureKind failureKindOf(Object? error) =>
    error is ShelfFailure ? error.kind : ShelfFailureKind.unexpected;
