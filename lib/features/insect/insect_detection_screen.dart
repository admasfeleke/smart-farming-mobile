import 'package:flutter/material.dart';

import '../../language_store.dart';
import '../../localization.dart';
import '../../widgets/farm_ui.dart';
import 'insect_model_registry.dart';

class InsectDetectionScreen extends StatefulWidget {
  const InsectDetectionScreen({super.key});

  @override
  State<InsectDetectionScreen> createState() => _InsectDetectionScreenState();
}

class _InsectDetectionScreenState extends State<InsectDetectionScreen> {
  late Future<void> _modelFuture;

  @override
  void initState() {
    super.initState();
    _modelFuture = InsectModelRegistry.instance.warmUp();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return FutureBuilder<void>(
          future: _modelFuture,
          builder: (context, _) {
            final registry = InsectModelRegistry.instance;
            final manifest = registry.manifest;
            final installed = registry.isInstalled;
            return FarmSurface(
              padding: EdgeInsets.zero,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FarmHeroCard(
                    imageAsset: 'assets/images/home/field_prevention.jpg',
                    eyebrow: L.t(lang, 'pest_detection'),
                    title: installed
                        ? L.t(lang, 'insect_detection_ready_title')
                        : L.t(lang, 'insect_detection_not_installed_title'),
                    body: installed
                        ? L.t(lang, 'insect_detection_ready_body')
                        : L.t(lang, 'insect_detection_not_installed_body'),
                    trailing: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        installed ? Icons.bug_report_rounded : Icons.inventory_2_outlined,
                        color: const Color(0xFF41670F),
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FarmPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDEF9D),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                installed
                                    ? Icons.verified_rounded
                                    : Icons.pending_actions_rounded,
                                color: const Color(0xFF41670F),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                installed
                                    ? L.t(lang, 'insect_model_alignment')
                                    : L.t(lang, 'insect_model_required'),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF1E2A12),
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          installed
                              ? L.t(lang, 'insect_model_metadata', params: {
                                  'model': manifest?.modelId ?? '--',
                                  'classes': '${manifest?.classCount ?? 0}',
                                  'task': manifest?.task ?? 'classification',
                                })
                              : L.t(lang, 'insect_model_expected_bundle', params: {
                                  'path': InsectModelRegistry.manifestAsset,
                                }),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InsectScopeChip(label: L.t(lang, 'insect_scope_pests')),
                            const _InsectScopeChip(label: 'IP102'),
                            _InsectScopeChip(label: L.t(lang, 'insect_scope_separate')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FarmPanel(
                    color: installed ? const Color(0xFFEAF3CF) : const Color(0xFFFFF5D7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          installed ? Icons.task_alt_rounded : Icons.info_outline_rounded,
                          color: installed ? const Color(0xFF41670F) : const Color(0xFF8A6500),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            installed
                                ? L.t(lang, 'insect_next_steps')
                                : L.t(lang, 'insect_blocked_notice'),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: installed
                                      ? const Color(0xFF24420C)
                                      : const Color(0xFF57430A),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InsectScopeChip extends StatelessWidget {
  final String label;

  const _InsectScopeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_circle_rounded, size: 18),
      label: Text(label),
      backgroundColor: const Color(0xFFEAF3CF),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
    );
  }
}
