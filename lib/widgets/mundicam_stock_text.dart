import 'package:flutter/material.dart';

import '../models/mundicam_product.dart';

class MundicamStockText extends StatelessWidget {
  final MundicamProduct product;
  final TextStyle? style;

  const MundicamStockText({
    super.key,
    required this.product,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (!product.canViewStock) {
      return const SizedBox.shrink();
    }

    final text = product.stockText;
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ?? Theme.of(context).textTheme.bodySmall,
    );
  }
}
