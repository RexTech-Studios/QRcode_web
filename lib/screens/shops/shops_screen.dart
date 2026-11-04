import 'package:flutter/material.dart';

import '../../widgets/coming_soon_placeholder.dart';

class ShopsScreen extends StatelessWidget {
  const ShopsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonPlaceholder(
      icon: Icons.storefront_rounded,
      title: 'Shops',
      subtitle: 'Manage all your shops and their review links here next.',
    );
  }
}
