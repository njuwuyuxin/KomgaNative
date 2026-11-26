import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/l10n/connection_failure_text.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/certificate_panel.dart';
import 'package:yomu/src/widgets/saved_servers_card.dart';
import 'package:material_ui/material_ui.dart';

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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final disconnected = session is SessionDisconnected ? session : null;
    final submitting = disconnected?.submitting ?? false;
    final failure = disconnected?.failure;
    final error = failure == null ? null : l10n.connectionFailureTitle(failure);
    final hint = failure == null ? null : l10n.connectionFailureHint(failure);
    final certificate = disconnected?.certificate;
    final savedServers =
        ref.watch(serverListProvider).value ?? const <StoredServer>[];

    // HTTP + 公网时提前警告，避免用户把凭据明文发出去。
    String? insecureWarning;
    try {
      final address = ServerAddress.parse(_url.text);
      if (address.isInsecureRemote) insecureWarning = l10n.insecureWarning;
    } on FormatException {
      insecureWarning = null;
    }

    return Scaffold(
      body: GlassPageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.formMaxWidth,
                ),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('Yomu', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.connectSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      GlassSurface(
                        shape: AppShapes.of(context, AppShapes.panel),
                        shadows: AppShadows.card,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              GlassSegmentedControl<_AuthMode>(
                                segments: <GlassSegment<_AuthMode>>[
                                  GlassSegment<_AuthMode>(
                                    value: _AuthMode.account,
                                    label: l10n.account,
                                    icon: Icons.person_outline,
                                  ),
                                  GlassSegment<_AuthMode>(
                                    value: _AuthMode.apiKey,
                                    label: l10n.apiKey,
                                    icon: Icons.key_outlined,
                                  ),
                                ],
                                selected: _mode,
                                onSelected: (mode) {
                                  if (submitting) return;
                                  setState(() => _mode = mode);
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextField(
                                controller: _url,
                                enabled: !submitting,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autofillHints: const <String>[
                                  AutofillHints.url,
                                ],
                                autocorrect: false,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: l10n.serverAddress,
                                  hintText: l10n.serverAddressHint,
                                  prefixIcon: const Icon(Icons.dns_outlined),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (_mode == _AuthMode.account) ...<Widget>[
                                TextField(
                                  controller: _username,
                                  enabled: !submitting,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const <String>[
                                    AutofillHints.username,
                                    AutofillHints.email,
                                  ],
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: l10n.email,
                                    prefixIcon: const Icon(
                                      Icons.alternate_email,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _password,
                                  enabled: !submitting,
                                  obscureText: !_showPassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const <String>[
                                    AutofillHints.password,
                                  ],
                                  onSubmitted: (_) {
                                    if (!submitting) unawaited(_submit());
                                  },
                                  decoration: InputDecoration(
                                    labelText: l10n.password,
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      tooltip: _showPassword
                                          ? l10n.hidePassword
                                          : l10n.showPassword,
                                    ),
                                  ),
                                ),
                              ] else
                                TextField(
                                  controller: _apiKey,
                                  enabled: !submitting,
                                  textInputAction: TextInputAction.done,
                                  autocorrect: false,
                                  onSubmitted: (_) {
                                    if (!submitting) unawaited(_submit());
                                  },
                                  decoration: InputDecoration(
                                    labelText: l10n.apiKey,
                                    hintText: l10n.apiKeyHint,
                                    prefixIcon: const Icon(Icons.key_outlined),
                                  ),
                                ),
                              if (insecureWarning != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.md),
                                _Banner(
                                  icon: Icons.warning_amber_outlined,
                                  text: insecureWarning,
                                  background: theme.colorScheme.errorContainer,
                                  foreground:
                                      theme.colorScheme.onErrorContainer,
                                ),
                              ],
                              if (certificate != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.md),
                                CertificatePanel(
                                  certificate: certificate,
                                  busy: submitting,
                                  onTrust: () => ref
                                      .read(sessionProvider.notifier)
                                      .trustCertificate(),
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
                                  foreground:
                                      theme.colorScheme.onErrorContainer,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              GlassPillButton(
                                expanded: true,
                                busy: submitting,
                                icon: Icons.login,
                                label: l10n.connect,
                                onPressed: submitting ? null : _submit,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (savedServers.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        SavedServersCard(
                          servers: savedServers,
                          enabled: !submitting,
                          onSelect: (StoredServer server) => unawaited(
                            ref.read(sessionProvider.notifier).switchTo(server),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.passwordFootnote,
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
          Icon(icon, size: AppSizes.iconMd, color: foreground),
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
