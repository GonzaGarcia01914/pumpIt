import 'package:flutter/material.dart';

/// Applies a soft glow when the pointer hovers the wrapped [child].
/// Used to keep clickable areas consistent across different surfaces.
class HoverGlow extends StatefulWidget {
  const HoverGlow({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.glowColor,
    this.intensity = 0.35,
    this.blurRadius = 32,
    this.spreadRadius = -8,
    this.shadowOffset = const Offset(0, 18),
    this.translateOnHover = 0,
    this.duration = const Duration(milliseconds: 160),
  });

  final Widget child;
  final bool enabled;
  final BorderRadiusGeometry borderRadius;
  final Color? glowColor;
  final double intensity;
  final double blurRadius;
  final double spreadRadius;
  final Offset shadowOffset;
  final double translateOnHover;
  final Duration duration;

  @override
  State<HoverGlow> createState() => _HoverGlowState();
}

class _HoverGlowState extends State<HoverGlow> {
  bool _hovered = false;

  void _update(bool hovered) {
    if (!widget.enabled || _hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final color =
        widget.glowColor ??
        Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: widget.intensity);
    final transform = widget.translateOnHover == 0 || !_hovered
        ? null
        : (Matrix4.identity()..translate(0.0, -widget.translateOnHover));

    return MouseRegion(
      onEnter: (_) => _update(true),
      onExit: (_) => _update(false),
      child: AnimatedContainer(
        duration: widget.duration,
        curve: Curves.easeOut,
        transform: transform,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: color,
                    blurRadius: widget.blurRadius,
                    spreadRadius: widget.spreadRadius,
                    offset: widget.shadowOffset,
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}
