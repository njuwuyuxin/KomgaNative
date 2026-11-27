import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 连接页账号密码 / API Key 输入段（从 350 行的 `connection_screen.dart` 拆出，P3）。
class ConnectionCredentialsFields extends StatelessWidget {
  const ConnectionCredentialsFields({
    super.key,
    required this.useAccount,
    required this.submitting,
    required this.showPassword,
    required this.usernameController,
    required this.passwordController,
    required this.apiKeyController,
    required this.onToggleShowPassword,
    required this.onSubmit,
  });

  final bool useAccount;
  final bool submitting;
  final bool showPassword;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController apiKeyController;
  final VoidCallback onToggleShowPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!useAccount) {
      return TextField(
        controller: apiKeyController,
        enabled: !submitting,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        onSubmitted: (_) {
          if (!submitting) onSubmit();
        },
        decoration: InputDecoration(
          labelText: l10n.apiKey,
          hintText: l10n.apiKeyHint,
          prefixIcon: const Icon(Icons.key_outlined),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: usernameController,
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
            prefixIcon: const Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: passwordController,
          enabled: !submitting,
          obscureText: !showPassword,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onSubmitted: (_) {
            if (!submitting) onSubmit();
          },
          decoration: InputDecoration(
            labelText: l10n.password,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: onToggleShowPassword,
              icon: Icon(
                showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              tooltip: showPassword ? l10n.hidePassword : l10n.showPassword,
            ),
          ),
        ),
      ],
    );
  }
}

/// 连接页警告与错误横幅。
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({
    super.key,
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
