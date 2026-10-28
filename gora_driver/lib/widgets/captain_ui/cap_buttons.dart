import 'package:flutter/material.dart';
import 'cap_tokens.dart';

enum CapButtonTone { primary, secondary, danger, success, outline }

/// Big full-width button — the single strong CTA of a screen.
class CapButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final CapButtonTone tone;
  final double height;
  const CapButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.tone = CapButtonTone.primary,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, BorderSide side) = switch (tone) {
      CapButtonTone.primary => (Cap.navy, Colors.white, BorderSide.none),
      CapButtonTone.secondary => (Cap.tile, Cap.ink, BorderSide.none),
      CapButtonTone.danger => (Cap.red, Colors.white, BorderSide.none),
      CapButtonTone.success => (Cap.green, Colors.white, BorderSide.none),
      CapButtonTone.outline => (Colors.transparent, Cap.ink, BorderSide(color: Cap.divider, width: 1.2)),
    };
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: loading ? bg : Cap.tile,
          disabledForegroundColor: loading ? fg : Cap.muted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: side),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              )
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: enabled ? fg : Cap.muted),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: enabled ? fg : Cap.muted)),
                ),
              ]),
      ),
    );
  }
}

/// Fixed bottom bar holding the screen's primary CTA. Honours the
/// gesture-bar inset and draws a hairline above itself.
class CapBottomBar extends StatelessWidget {
  final Widget child;
  final Widget? top;
  const CapBottomBar({super.key, required this.child, this.top});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Cap.surface,
          border: Border(top: BorderSide(color: Cap.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (top != null) ...[top!, const SizedBox(height: 10)],
              child,
            ]),
          ),
        ),
      );
}

/// Round tinted icon button with a caption — Call / Message / Navigate.
class CapRoundAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? background;
  final String? tooltip;
  final double size;
  const CapRoundAction({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.color,
    this.background,
    this.tooltip,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Cap.ink;
    Widget circle = Material(
      color: background ?? Cap.tile,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: fg, size: size * 0.46)),
      ),
    );
    if (tooltip != null) circle = Tooltip(message: tooltip!, child: circle);
    if (label == null) return circle;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      circle,
      const SizedBox(height: 6),
      Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 11.5)),
    ]);
  }
}

/// White circular control that floats over a map (menu, back, recenter ...).
class MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? foreground;
  final Color? background;
  final double size;
  final Widget? badge;
  const MapCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.foreground,
    this.background,
    this.size = 46,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = Material(
      color: background ?? Cap.surface,
      elevation: 3,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: 22, color: foreground ?? Cap.ink)),
      ),
    );
    if (badge != null) {
      btn = Stack(clipBehavior: Clip.none, children: [btn, Positioned(top: -2, right: -2, child: badge!)]);
    }
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
