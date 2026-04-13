import 'package:flutter/material.dart';
import 'package:breakpoint/breakpoint.dart';
import '../layouts/mobile_layout.dart';
import '../layouts/tablet_layout.dart';
import '../layouts/desktop_layout.dart';

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return BreakpointBuilder(
      builder: (context, breakpoint) {
        switch (breakpoint.window) {
          case WindowSize.xsmall:
            return const MobileLayout();
          case WindowSize.small:
            if (breakpoint.device == LayoutClass.smallTablet ||
                breakpoint.device == LayoutClass.largeTablet) {
              return const TabletLayout();
            }
            return const MobileLayout();
          case WindowSize.medium:
          case WindowSize.large:
          case WindowSize.xlarge:
            return const DesktopLayout();
        }
      },
    );
  }
}
