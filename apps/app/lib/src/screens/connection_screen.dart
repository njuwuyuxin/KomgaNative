import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/certificate_panel.dart';

/// 首次连接 / 重新连接页。
///
/// 两种模式：
/// - **Account**：用账号密码换一把客户端专用的 API Key（之后不再保存密码）；
/// - **API key**：直接在 Komga 后台建好 Key 粘贴进来（不碰密码，适合开了双步验证的用户）。
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

enum _AuthMode { account, apiKey }

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();

  _AuthMode _mode = _AuthMode.account;
  bool _showPassword = false;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(sessionProvider.notifier);
    if (_mode == _AuthMode.account) {
      await controller.connectWithPassword(
        rawUrl: _url.text,
        username: _username.text.trim(),
        password: _password.text,
      );
    } else {
      await controller.connectWithApiKey(
        rawUrl: _url.text,
        apiKey: _apiKey.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final disconnected = session is SessionDisconnected ? session : null;
    final submitting = disconnected?.submitting ?? false;
    final error = disconnected?.error;
    final hint = disconnected?.hint;
    final certificate = disconnected?.certificate;

    // HTTP + 公网时提前警告，避免用户把凭据明文发出去。
    // 注意措辞：端口只开 HTTPS 时我们会自动换协议，但第一次尝试确实带凭据，
    // 所以警告不能写成"可能会"。
    String? insecureWarning;
    try {
      final address = ServerAddress.parse(_url.text);
      if (address.isInsecureRemote) {
        insecureWarning =
            'This address is outside your local network and uses plain HTTP. '
            'If the port only accepts HTTPS the app switches automatically; '
            'otherwise your credentials would be sent unencrypted.';
      }
    } on FormatException {
      insecureWarning = null;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('KomgaNative', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Connect to your Komga server',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _url,
                    enabled: !submitting,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server address',
                      hintText: 'https://komga.example.com',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<_AuthMode>(
                    segments: const <ButtonSegment<_AuthMode>>[
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.account,
                        label: Text('Account'),
                        icon: Icon(Icons.person_outline),
                      ),
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.apiKey,
                        label: Text('API key'),
                        icon: Icon(Icons.key_outlined),
                      ),
                    ],
                    selected: <_AuthMode>{_mode},
                    onSelectionChanged: submitting
                        ? null
                        : (Set<_AuthMode> selection) =>
                              setState(() => _mode = selection.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_mode == _AuthMode.account) ...<Widget>[
                    TextField(
                      controller: _username,
                      enabled: !submitting,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _password,
                      enabled: !submitting,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                        ),
                      ),
                    ),
                  ] else
                    TextField(
                      controller: _apiKey,
                      enabled: !submitting,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API key',
                        hintText: 'Komga → Account settings → API keys',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                    ),
                  if (insecureWarning != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _Banner(
                      icon: Icons.warning_amber_outlined,
                      text: insecureWarning,
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                    ),
                  ],
                  if (certificate != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    CertificatePanel(
                      certificate: certificate,
                      busy: submitting,
                      onTrust: () =>
                          ref.read(sessionProvider.notifier).trustCertificate(),
                      onCancel: () => ref
                          .read(sessionProvider.notifier)
                          .cancelCertificatePrompt(),
                    ),
                  ] else if (error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _Banner(
                      icon: Icons.error_outline,
                      text: hint == null ? error : '$error\n$hint',
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: submitting ? null : _submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Your password is only used once to create an API key; '
                    'the key is stored in the system keychain.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
