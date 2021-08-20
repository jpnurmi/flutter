// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'material_state.dart';

/// Controls the default mouse cursors in a widget subtree.
///
/// The mouse cursor theme is honored by clickable material widgets.
class MouseCursorTheme extends InheritedTheme {
  /// Creates a mouse cursor theme that controls the mouse cursor of descendant
  /// widgets.
  const MouseCursorTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// Creates a mouse cursor theme that controls the mouse cursor of descendant
  /// widgets, and merges in the current mouse cursor theme, if any.
  static Widget merge({
    Key? key,
    required MouseCursorThemeData data,
    required Widget child,
  }) {
    return Builder(
      builder: (BuildContext context) {
        return MouseCursorTheme(
          key: key,
          data: _getInheritedMouseCursorThemeData(context).merge(data),
          child: child,
        );
      },
    );
  }

  /// The mouse cursors to use for widgets in this subtree.
  final MouseCursorThemeData data;

  /// The data from the closest instance of this class that encloses the given
  /// context, if any.
  ///
  /// If there is no ambient mouse cursor theme, defaults to [MouseCursorThemeData.fallback].
  /// The returned [MouseCursorThemeData] is concrete (all values are non-null; see
  /// [MouseCursorThemeData.isConcrete]). Any properties on the ambient mouse cursor
  /// theme that are null get defaulted to the values specified on
  /// [MouseCursorThemeData.fallback].
  ///
  /// The [Theme] widget introduces a [MouseCursorTheme] widget set to the
  /// [ThemeData.mouseCursorTheme], so this will typically default to the mouse
  /// cursor theme from the ambient [Theme].
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// MouseCursorThemeData theme = MouseCursorTheme.of(context);
  /// ```
  static MouseCursorThemeData of(BuildContext context) {
    final MouseCursorThemeData themeData = _getInheritedMouseCursorThemeData(context).resolve(context);
    return themeData.isConcrete
      ? themeData
      : themeData.copyWith(
        clickable: themeData.clickable ?? const MouseCursorThemeData.fallback().clickable,
      );
  }

  static MouseCursorThemeData _getInheritedMouseCursorThemeData(BuildContext context) {
    final MouseCursorTheme? theme = context.dependOnInheritedWidgetOfExactType<MouseCursorTheme>();
    return theme?.data ?? const MouseCursorThemeData.fallback();
  }

  @override
  bool updateShouldNotify(MouseCursorTheme oldWidget) => data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) {
    return MouseCursorTheme(data: data, child: child);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    data.debugFillProperties(properties);
  }
}

/// Defines mouse cursors.
///
/// Used by [MouseCursorTheme] to control mouse cursors in a widget subtree.
///
/// To obtain the current mouse cursor theme, use [MouseCursorTheme.of]. To
/// convert a mouse cursor theme to a version with all the fields filled in, use
/// [MouseCursorThemeData.fallback].
@immutable
class MouseCursorThemeData with Diagnosticable {
  /// Creates a mouse cursor theme data.
  const MouseCursorThemeData({this.clickable});

  /// Creates a mouse cursor theme with some reasonable default values.
  ///
  /// The [clickable] mouse cursor is [MaterialStateMouseCursor.clickable].
  const MouseCursorThemeData.fallback()
    : clickable = MaterialStateMouseCursor.clickable;

  /// Creates a copy of this mouse cursor theme but with the given fields replaced
  /// with the new values.
  MouseCursorThemeData copyWith({
    MaterialStateProperty<MouseCursor?>? clickable,
  }) {
    return MouseCursorThemeData(
      clickable: clickable ?? this.clickable,
    );
  }

  /// Returns a new mouse cursor theme that matches this mouse cursor theme but
  /// with some values replaced by the non-null parameters of the given mouse
  /// cursor theme. If the given mouse cursor theme is null, simply returns this
  /// mouse cursor theme.
  MouseCursorThemeData merge(MouseCursorThemeData? other) {
    if (other == null) {
      return this;
    }
    return copyWith(clickable: other.clickable);
  }

  /// Called by [MouseCursorTheme.of] to convert this instance to a [MouseCursorThemeData]
  /// that fits the given [BuildContext].
  ///
  /// This method gives the ambient [MouseCursorThemeData] a chance to update itself,
  /// after it's been retrieved by [MouseCursorTheme.of], and before being returned as
  /// the final result.
  ///
  /// The default implementation returns this [MouseCursorThemeData] as-is.
  MouseCursorThemeData resolve(BuildContext context) => this;

  /// Whether all the properties of this object are non-null.
  bool get isConcrete => clickable != null;

  /// The default clickable mouse cursor.
  final MaterialStateProperty<MouseCursor?>? clickable;

  /// Interpolate between two mouse cursor theme data objects.
  ///
  /// {@macro dart.ui.shadow.lerp}
  static MouseCursorThemeData lerp(MouseCursorThemeData? a, MouseCursorThemeData? b, double t) {
    if (identical(a, b) && a != null) {
      return a;
    }
    return MouseCursorThemeData(
      clickable: t < 0.5 ? a?.clickable : b?.clickable,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is MouseCursorThemeData
        && other.clickable == clickable;
  }

  @override
  int get hashCode => clickable.hashCode;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<MaterialStateProperty<MouseCursor?>>('clickable', clickable, defaultValue: null));
  }
}
