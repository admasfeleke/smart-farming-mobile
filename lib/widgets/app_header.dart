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
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFF2F5E12), Color(0xFF6B8E16)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2F5E12).withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 12),
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
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
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
              const SizedBox(width: 10),
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
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSubtitle ? subtitleText : L.t(lang, 'app_name'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _HeaderIconButton(
                onPressed: onSearchTap ?? () {},
                icon: Icons.search_rounded,
                tooltip: L.t(lang, 'search'),
              ),
              const SizedBox(width: 6),
              _HeaderIconButton(
                onPressed: onRefreshTap ?? () {},
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
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 23),
          ),
        ),
      ),
    );
  }
}
