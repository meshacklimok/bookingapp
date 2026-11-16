import 'package:flutter/material.dart';

/// Five stars, [rating] of them filled. With [onChanged], tapping a star sets the rating.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.onChanged, this.size = 18});

  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(i),
            child: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: color),
          ),
      ],
    );
  }
}
