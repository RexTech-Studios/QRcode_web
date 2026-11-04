import 'package:flutter/material.dart';

import '../../widgets/coming_soon_placeholder.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonPlaceholder(
      icon: Icons.bar_chart_rounded,
      title: 'Analytics',
      subtitle: 'Scan and feedback analytics will appear here next.',
    );
  }
}
