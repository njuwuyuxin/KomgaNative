import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/session/certificate_prompt.dart';

/// 证书不受信任时给用户看的面板。
///
/// 设计取舍：**不做"默认信任 + 记住我的选择"**。自建服务器的证书过期很常见，
/// 但客户端不能替用户决定"这张证书可以信"——把 CN、颁发者、到期时间、指纹
/// 摆出来，让他自己判断，然后只固定这一张证书。
class CertificatePanel extends StatelessWidget {
  const CertificatePanel({
    required this.certificate,
    required this.onTrust,
    required this.onCancel,
    this.busy = false,
    super.key,
  });

  final CertificatePrompt certificate;
  final VoidCallback onTrust;
  final VoidCallback onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reason = certificate.expired
        ? l10n.certificateExpiredReason(certificate.expiresText)
        : certificate.selfSigned
        ? l10n.certificateSelfSignedReason
        : l10n.certificateUntrustedReason;

    return Container(
      key: const Key('certificate-panel'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.gpp_maybe_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.certificateUntrusted,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reason,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(label: l10n.issuedTo, value: certificate.commonName),
          _Row(
            label: l10n.issuedBy,
            value: certificate.selfSigned
                ? l10n.selfSignedSuffix(certificate.issuerName)
                : certificate.issuerName,
          ),
          _Row(
            label: certificate.expired ? l10n.expiredOn : l10n.validUntil,
            value: certificate.expiresAt == null
                ? l10n.unknownDate
                : certificate.expiresText,
          ),
          _Row(label: l10n.sha256, value: certificate.fingerprint),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.certificateAdvice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wrap 而不是 Row：大字号/窄屏时两个按钮并排放不下，
          // 换行总比"按钮被裁掉一半"好。
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.end,
              children: <Widget>[
                TextButton(
                  // 墨水屏主题里 primary 是黑的，默认按钮文字会淹没在面板底色里。
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: busy ? null : onCancel,
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onErrorContainer,
                    foregroundColor: scheme.errorContainer,
                  ),
                  onPressed: busy ? null : onTrust,
                  child: Text(l10n.connectAnyway),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onErrorContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            // 固定标签列宽，值才能对齐；大字缩放时标签自己换行，不压住值。
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                // 等宽数字让指纹逐位对齐，方便人眼分组核对。
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
