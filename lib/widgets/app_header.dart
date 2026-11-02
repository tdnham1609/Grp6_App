import 'package:flutter/material.dart';

/// Header widget dùng chung cho ứng dụng Sinh Tử (Dead Man's Switch)
class AppHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const AppHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.shield_moon_rounded,
          color: Color(0xFF50E3C2),
          size: 38,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFB2DFDB),
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
