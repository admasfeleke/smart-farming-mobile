import 'package:flutter/material.dart';
import '../language_store.dart';
import '../localization.dart';

class AppHeader extends StatelessWidget {
  final String? titleKey;
  final String? title;
  final String? subtitle;
  final VoidCallback? onMenuTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onRefreshTap;
  const AppHeader({
    super.key,
    this.titleKey,
    this.title,
    this.subtitle,
    this.onMenuTap,
    this.onSearchTap,
    this.onRefreshTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final rawTitle = title;
        final resolvedTitle = (rawTitle != null && rawTitle.trim().isNotEmpty)
            ? rawTitle.trim()
            : (titleKey != null ? L.t(lang, titleKey!) : '');
        final subtitleText = (subtitle ?? '').trim();
        final hasSubtitle = subtitleText.isNotEmpty;

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF18370D), Color(0xFF4F7D12)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF17380D).withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              _HeaderIconButton(
                onPressed: onMenuTap,
                icon: Icons.menu_rounded,
                tooltip: L.t(lang, 'menu'),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                ),
                child: Image.asset(
                  'assets/images/logo/smart.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.eco_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolvedTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSubtitle ? subtitleText : L.t(lang, 'app_name'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFE7F6C0),
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _HeaderIconButton(
                onPressed: onSearchTap,
                icon: Icons.search_rounded,
                tooltip: L.t(lang, 'search'),
              ),
              const SizedBox(width: 6),
              _HeaderIconButton(
                onPressed: onRefreshTap,
                icon: Icons.sync_rounded,
                tooltip: L.t(lang, 'refresh'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  const _HeaderIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: enabled ? 0.14 : 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: enabled ? 1 : 0.42),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
