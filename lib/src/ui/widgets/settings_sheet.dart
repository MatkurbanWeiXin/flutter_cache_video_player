import 'package:flutter/material.dart';
import '../../utils/size_formatter.dart';
import '../themes/theme_controller.dart';

/// 设置底部弹出组件，包含主题切换和缓存管理。
/// Settings bottom sheet containing theme switching and cache management.
class SettingsSheet extends StatelessWidget {
  final ThemeController themeController;
  final int currentCacheSize;
  final int maxCacheSize;
  final VoidCallback? onClearCache;

  const SettingsSheet({
    super.key,
    required this.themeController,
    this.currentCacheSize = 0,
    this.maxCacheSize = 2 * 1024 * 1024 * 1024,
    this.onClearCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('设置', style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: 16),
              // Theme
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('主题'),
                trailing: ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeController,
                  builder: (context, mode, _) {
                    return SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode)),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                      ],
                      selected: {mode},
                      onSelectionChanged: (modes) {
                        themeController.setThemeMode(modes.first);
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              // Cache info
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('缓存占用'),
                subtitle: Text(
                  '${SizeFormatter.format(currentCacheSize)} / ${SizeFormatter.format(maxCacheSize)}',
                ),
                trailing: TextButton(onPressed: onClearCache, child: const Text('清除')),
              ),
              // Cache progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: maxCacheSize > 0 ? currentCacheSize / maxCacheSize : 0,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
