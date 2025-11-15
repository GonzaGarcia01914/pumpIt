import 'package:flutter/material.dart';

class SoftSurface extends StatefulWidget {
  const SoftSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 26,
    this.gradient,
    this.color,
    this.enableHover = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Gradient? gradient;
  final Color? color;
  final bool enableHover;

  @override
  State<SoftSurface> createState() => _SoftSurfaceState();
}

class _SoftSurfaceState extends State<SoftSurface> {
  bool _isHovered = false;

  void _updateHover(bool value) {
    if (!widget.enableHover) return;
    if (_isHovered != value) {
      setState(() => _isHovered = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedRadius = BorderRadius.circular(widget.borderRadius);
    final surfaceColor = (widget.color ?? theme.colorScheme.surface).withValues(
      alpha: 0.96,
    );
    final accent = theme.colorScheme.primary;

    final resolvedGradient = widget.gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surfaceColor.withValues(alpha: 0.95),
            surfaceColor.withValues(alpha: 0.8),
          ],
        );

    final baseShadow = BoxShadow(
      color: Colors.black.withValues(alpha: _isHovered ? 0.5 : 0.65),
      offset: Offset(0, _isHovered ? 20 : 28),
      blurRadius: _isHovered ? 46 : 40,
      spreadRadius: -18,
    );

    final glowShadow = BoxShadow(
      color: accent.withValues(alpha: _isHovered ? 0.2 : 0.12),
      blurRadius: _isHovered ? 40 : 32,
      spreadRadius: -10,
    );

    Widget surface = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: resolvedRadius,
        color: widget.gradient == null ? null : Colors.transparent,
        gradient: resolvedGradient,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [baseShadow, glowShadow],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: resolvedRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
        ),
        child: Padding(
          padding: widget.padding ?? const EdgeInsets.all(24),
          child: widget.child,
        ),
      ),
    );

    if (widget.enableHover) {
      surface = MouseRegion(
        onEnter: (_) => _updateHover(true),
        onExit: (_) => _updateHover(false),
        child: surface,
      );
    }

    return surface;
  }
}
