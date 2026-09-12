import 'package:flutter/material.dart';
import '../core/notifications/app_toast.dart';

abstract final class FormScrollHelper {
  FormScrollHelper._();

  /// Scrolls the nearest Scrollable ancestor to the first invalid FormField,
  /// focuses the input field, and shows the specific error message.
  static void scrollToFirstError(BuildContext context) {
    Element? firstErrorElement;
    String? errorMessage;

    void visitor(Element element) {
      if (firstErrorElement != null) return;
      if (element.widget is FormField) {
        final state = (element as StatefulElement).state;
        if (state is FormFieldState && state.hasError) {
          firstErrorElement = element;
          errorMessage = state.errorText;
          return;
        }
      }
      element.visitChildren(visitor);
    }

    context.visitChildElements(visitor);

    if (firstErrorElement != null) {
      Scrollable.ensureVisible(
        firstErrorElement!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );

      // Attempt to focus the input field
      try {
        final focusNode = FocusScope.of(firstErrorElement!);
        focusNode.requestFocus();
      } catch (_) {}

      final msg = (errorMessage != null && errorMessage!.isNotEmpty)
          ? errorMessage!
          : 'Please check and correct the highlighted field above.';
      AppToast.error(context, msg);
    }
  }
}
