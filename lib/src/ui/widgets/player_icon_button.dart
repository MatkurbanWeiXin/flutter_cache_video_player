import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 播放器控件中通用的圆形图标按钮。
/// 点击具有按压缩放反馈与半透明描边，图标默认为纯白色、纤细的 Apple 风格。
///
/// Reusable round icon button used by the player overlay controls.
/// Provides a scale-press feedback and a subtle circular backdrop so that
/// Apple SF-Symbols–style glyphs remain legible on bright video frames.
class PlayerIconButton extends StatefulWidget {
  /// 按钮上的图标（通常来自 [CupertinoIcons]）。
  /// The icon to render, typically sourced from [CupertinoIcons].
  final IconData icon;

  /// 图标尺寸。
  /// Icon size in logical pixels.
  final double size;

  /// 图标颜色，默认纯白。
  /// Icon tint color. Defaults to pure white.
  final Color color;

  /// 点击回调。为 null 时按钮呈禁用态（半透明、不响应手势）。
  /// Tap callback. When null the button appears disabled and ignores gestures.
  final VoidCallback? onPressed;

  /// 是否绘制一个极轻的圆形描边背景，帮助在明亮画面下提升辨识度。
  /// Whether to render a faint circular chip around the glyph for clarity.
  final bool showChip;

  /// 无障碍语义标签。
  /// Semantics label used by screen readers.
  final String? semanticsLabel;

  /// 图标外的命中区域内边距，确保触摸目标足够大。
  /// Hit-area padding around the icon to guarantee a comfortable tap target.
  final EdgeInsets padding;

  const PlayerIconButton({
    super.key,
    required this.icon,
    this.size = 24,
    this.color = Colors.white,
    this.onPressed,
    this.showChip = false,
    this.semanticsLabel,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final effectiveColor = widget.color.withValues(alpha: enabled ? 1.0 : 0.4);

    Widget child = Icon(
      widget.icon,
      size: widget.size,
      color: effectiveColor,
      shadows: const <Shadow>[
        Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 1)),
      ],
    );

    if (widget.showChip) {
      child = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.6),
        ),
        child: child,
      );
    }

    final button = Padding(padding: widget.padding, child: child);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 0.88 : 1.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _pressed ? 0.75 : 1.0,
            child: button,
          ),
        ),
      ),
    );
  }
}
