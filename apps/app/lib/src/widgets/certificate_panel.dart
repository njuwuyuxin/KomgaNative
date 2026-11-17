import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                  'The server’s certificate is not trusted',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            certificate.reason,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(label: 'Issued to', value: certificate.commonName),
          _Row(
            label: 'Issued by',
            value: certificate.selfSigned
                ? '${certificate.issuerName} (self-signed)'
                : certificate.issuerName,
          ),
          _Row(
            label: certificate.expired ? 'Expired on' : 'Valid until',
            value: certificate.expiresText,
          ),
          _Row(label: 'SHA-256', value: certificate.fingerprint),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Only continue if you run this server. Continuing pins this exact '
            'certificate; a different one will be blocked next time.',
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
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onErrorContainer,
                    foregroundColor: scheme.errorContainer,
                  ),
                  onPressed: busy ? null : onTrust,
                  child: const Text('Connect anyway'),
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
