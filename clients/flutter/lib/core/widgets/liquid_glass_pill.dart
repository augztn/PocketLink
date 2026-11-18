import 'package:material_ui/material_ui.dart';

/// Opaque surface shared by the floating navigation and action controls.
class SolidPill extends StatelessWidget {
  const SolidPill({
    required this.child,
    required this.radius,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: radius,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    ),
  );
}
