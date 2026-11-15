import 'package:flutter/material.dart';

/// Shared compact search control used by file and media library screens.
class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13, color: Colors.white54),
        prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Colors.white70),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        suffixIcon: controller.text.isEmpty ? null : IconButton(
          tooltip: 'Clear search',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            controller.clear();
            onChanged('');
          },
          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
        ),
        filled: true,
        fillColor: const Color(0xFF1C1C1E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
    ),
  );
}
