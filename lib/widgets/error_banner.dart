import 'package:flutter/material.dart';

import '../language_store.dart';
import '../localization.dart';

class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onErrorContainer;

    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: Text(L.t(LanguageStore.notifier.value, 'retry')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void showErrorBanner(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearMaterialBanners();
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: L.t(LanguageStore.notifier.value, 'retry'),
              onPressed: onRetry,
            ),
    ),
  );
}
