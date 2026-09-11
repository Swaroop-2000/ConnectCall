import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class AvatarCircle extends StatelessWidget {
  final String name;
  final double radius;
  final Color? color;
  final String? photoUrl;

  const AvatarCircle({
    super.key,
    required this.name,
    this.radius = 24,
    this.color,
    this.photoUrl,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color get _bgColor {
    if (color != null) return color!;
    final colors = [
      const Color(0xFF6C63FF),
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFF5722),
      const Color(0xFF9C27B0),
      const Color(0xFF2196F3),
    ];
    int idx = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return colors[idx];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bgColor,
        image: (photoUrl != null && photoUrl!.isNotEmpty)
            ? DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? null
          : Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            ),
    );
  }
}

class CommonButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final IconData? icon;

  const CommonButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

class CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: size * 0.45),
          ),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class OnlineDot extends StatelessWidget {
  final bool isOnline;
  final double size;

  const OnlineDot({super.key, required this.isOnline, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? AppColors.callGreen : Colors.grey,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}
