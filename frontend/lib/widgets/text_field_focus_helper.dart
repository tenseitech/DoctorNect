import 'package:flutter/material.dart';

/// Focus helpers so automation tools and users replace field text instead of appending.
abstract final class TextFieldFocusHelper {
  static void bindSelectAllOnFocus({
    required FocusNode focusNode,
    required TextEditingController controller,
  }) {
    focusNode.addListener(() {
      if (!focusNode.hasFocus) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!focusNode.hasFocus) return;
        final text = controller.text;
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      });
    });
  }
}
