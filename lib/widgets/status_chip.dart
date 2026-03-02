import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final String text;
  final Color bgColor;
  final Color fgColor;

  const StatusChip({
    super.key,
    required this.text,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: fgColor.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}