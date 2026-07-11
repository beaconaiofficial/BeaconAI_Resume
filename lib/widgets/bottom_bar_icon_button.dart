import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BottomBarIconButton — icon-over-label button used in the bottom action
// bars of ResumeEditorScreen and PreviewEditScreen (Template/Print/Export).
// Previously duplicated as a private _BarButton class (plus an inline copy
// for Export) in both screens; consolidated here after both copies were
// found to share the same fixed-height overflow bug at large text scales.
//
// minHeight (not a fixed height) keeps the 48dp minimum tap target at
// default scale, while letting the icon+label column grow instead of
// overflowing once text scales up to the app's 200% accessibility override.
// ─────────────────────────────────────────────────────────────────────────────

class BottomBarIconButton extends StatelessWidget {
  const BottomBarIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color foregroundColor;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
