// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String? readLastLoginLocal(String key) => html.window.localStorage[key];

void writeLastLoginLocal(String key, String value) {
  html.window.localStorage[key] = value;
}

void removeLastLoginLocal(String key) {
  html.window.localStorage.remove(key);
}
