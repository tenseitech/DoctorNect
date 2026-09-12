import 'package:flutter/material.dart';

import '../core/layout/responsive_layout.dart';

class MobileScaffold extends StatelessWidget {
  const MobileScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.extendBody = false,
    /// When true, wraps [child] in a scroll view to avoid vertical overflow
    /// on small screens / large text scale / keyboard.
    this.scrollable = false,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final bool extendBody;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    Widget bodyChild = Padding(
      padding: padding,
      child: child,
    );
    if (scrollable) {
      bodyChild = SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: bodyChild,
      );
    }

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      extendBody: extendBody,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: !extendBody,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveLayout.contentMaxWidth(context),
            ),
            child: bodyChild,
          ),
        ),
      ),
    );
  }
}
