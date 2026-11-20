import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// [ConnectionFailure] → 当前语言本地化文案（ARC-11）。
extension ConnectionFailureText on AppLocalizations {
  String connectionFailureTitle(ConnectionFailure failure) =>
      switch (failure.kind) {
        ConnectionFailureKind.restoreFailed => connRestoreFailedTitle,
        ConnectionFailureKind.invalidAddress => connInvalidAddressTitle,
        ConnectionFailureKind.auth => connAuthTitle,
        ConnectionFailureKind.untrustedCertificate => connUntrustedCertTitle,
        ConnectionFailureKind.httpsRequired ||
        ConnectionFailureKind.httpsRefused => connHttpsOnlyTitle,
        ConnectionFailureKind.network => connNetworkTitle(failure.host ?? ''),
        ConnectionFailureKind.badRequest => connBadRequestTitle,
        ConnectionFailureKind.server => connServerTitle(
          '${failure.statusCode ?? '5xx'}',
        ),
        ConnectionFailureKind.protocol => connProtocolTitle,
        ConnectionFailureKind.unexpected => connUnexpectedTitle,
      };

  String? connectionFailureHint(ConnectionFailure failure) =>
      switch (failure.kind) {
        ConnectionFailureKind.restoreFailed => connRestoreFailedHint,
        ConnectionFailureKind.invalidAddress => connInvalidAddressHint,
        ConnectionFailureKind.auth => connAuthHint,
        ConnectionFailureKind.untrustedCertificate =>
          failure.certificateUnreadable ? connCertUnreadableHint : null,
        ConnectionFailureKind.httpsRequired => connHttpsTryUrlHint(
          failure.url ?? 'https://',
        ),
        ConnectionFailureKind.httpsRefused => connHttpsRefusedHint(
          failure.url ?? '',
        ),
        ConnectionFailureKind.network => connNetworkHint,
        ConnectionFailureKind.badRequest => connBadRequestHint,
        ConnectionFailureKind.server => connServerHint,
        ConnectionFailureKind.protocol => connProtocolHint,
        ConnectionFailureKind.unexpected => connUnexpectedHint,
      };
}
