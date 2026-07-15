import 'package:flutter/material.dart';

import '../models/mundicam_product.dart';

class MundicamPriceText extends StatelessWidget {
  final MundicamProduct product;
  final TextStyle? style;
  final bool showVatIncludedPrice;

  const MundicamPriceText({
    super.key,
    required this.product,
    this.style,
    this.showVatIncludedPrice = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = showVatIncludedPrice
        ? product.displayPriceIncludingTaxText
        : product.displayPriceText;

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
    );
  }
}
