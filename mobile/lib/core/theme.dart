import 'package:flutter/material.dart';

/// Derived from the web app's default `lavender` theme tokens
/// (frontend-ng/src/styles.css). Values to be reconciled with that block.
ThemeData buildAppTheme() {
  const accent = Color(0xFF6C5CE7);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: accent),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
