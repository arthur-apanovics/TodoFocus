import 'package:flutter/material.dart';

/// The fixed brand seed colour. Used where a theme-reactive colour isn't
/// reachable — currently the persistent focus notification's accent, which
/// the OS renders outside the app's widget tree. It also seeds the default
/// [AppThemeColor].
const Color kBrandColor = Color(0xFF2E7D32);

/// Bottom padding that scrollable lists apply so their final item can be
/// scrolled clear of a floating action button (Material's extended FAB is
/// ~48 dp tall, plus a 16 dp screen margin, plus slack for fat-finger taps).
const double kFabSafeBottomPadding = 88.0;
