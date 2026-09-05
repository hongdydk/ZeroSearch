import 'package:flutter/material.dart';

/// 쇼핑몰 UI 공통 디자인 토큰.
class MallTokens extends ThemeExtension<MallTokens> {
  const MallTokens({
    required this.productCardAspectRatio,
    required this.listRowPadding,
    required this.navHeight,
    required this.productGridColumns,
    required this.contentMaxWidth,
  });

  final double productCardAspectRatio;
  final EdgeInsets listRowPadding;
  final double navHeight;
  final int productGridColumns;
  final double contentMaxWidth;

  static const web = MallTokens(
    productCardAspectRatio: 0.78,
    listRowPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    navHeight: 56,
    productGridColumns: 4,
    contentMaxWidth: 1400,
  );

  static const app = MallTokens(
    productCardAspectRatio: 1,
    listRowPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    navHeight: 56,
    productGridColumns: 2,
    contentMaxWidth: double.infinity,
  );

  @override
  MallTokens copyWith({
    double? productCardAspectRatio,
    EdgeInsets? listRowPadding,
    double? navHeight,
    int? productGridColumns,
    double? contentMaxWidth,
  }) {
    return MallTokens(
      productCardAspectRatio: productCardAspectRatio ?? this.productCardAspectRatio,
      listRowPadding: listRowPadding ?? this.listRowPadding,
      navHeight: navHeight ?? this.navHeight,
      productGridColumns: productGridColumns ?? this.productGridColumns,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
    );
  }

  @override
  MallTokens lerp(ThemeExtension<MallTokens>? other, double t) {
    if (other is! MallTokens) return this;
    return MallTokens(
      productCardAspectRatio:
          productCardAspectRatio + (other.productCardAspectRatio - productCardAspectRatio) * t,
      listRowPadding: EdgeInsets.lerp(listRowPadding, other.listRowPadding, t)!,
      navHeight: navHeight + (other.navHeight - navHeight) * t,
      productGridColumns: productGridColumns,
      contentMaxWidth: contentMaxWidth + (other.contentMaxWidth - contentMaxWidth) * t,
    );
  }
}

MallTokens mallTokensOf(BuildContext context) {
  return Theme.of(context).extension<MallTokens>() ?? MallTokens.app;
}
