import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, dark }

enum ViewMode { pageTurner, scroll }

enum ReaderFont {
  serif('Serif', 'serif', ['Georgia', 'Times New Roman', 'Noto Serif']),
  sansSerif('Sans serif', 'sans-serif', ['Helvetica Neue', 'Arial', 'Roboto']),
  monospace('Monospace', 'monospace', ['Menlo', 'Courier New', 'Roboto Mono']),
  // TODO: bundle a dyslexia-friendly font (OpenDyslexic or Atkinson
  // Hyperlegible) as an asset. Until then this falls back to the platform font.
  dyslexiaFriendly('Dyslexia friendly', 'OpenDyslexic', ['Atkinson Hyperlegible', 'Verdana']);

  const ReaderFont(this.label, this.family, this.fallback);

  /// What a screen reader says for this choice.
  final String label;
  final String family;
  final List<String> fallback;
}

/// Display settings for the reader. Values outside the limits are clamped.
class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderTheme.light,
    double fontSize = 18,
    this.fontFamily = ReaderFont.serif,
    double lineHeight = 1.5,
    double letterSpacing = 0,
    double paragraphSpacing = 1.0,
    this.viewMode = ViewMode.pageTurner,
  })  : _fontSize = fontSize,
        _lineHeight = lineHeight,
        _letterSpacing = letterSpacing,
        _paragraphSpacing = paragraphSpacing;

  static const minFontSize = 12.0, maxFontSize = 40.0, fontSizeStep = 2.0;
  static const minLineHeight = 1.0, maxLineHeight = 2.5;
  static const maxLetterSpacing = 0.2;
  static const maxParagraphSpacing = 3.0;

  final ReaderTheme theme;
  final ReaderFont fontFamily;
  final ViewMode viewMode;
  final double _fontSize, _lineHeight, _letterSpacing, _paragraphSpacing;

  double get fontSize => _fontSize.clamp(minFontSize, maxFontSize);
  double get lineHeight => _lineHeight.clamp(minLineHeight, maxLineHeight);

  /// In ems.
  double get letterSpacing => _letterSpacing.clamp(0.0, maxLetterSpacing);

  /// Space between paragraphs, in ems.
  double get paragraphSpacing => _paragraphSpacing.clamp(0.0, maxParagraphSpacing);

  // Both pairs exceed the WCAG AA 4.5:1 contrast ratio by a wide margin.
  Color get backgroundColor =>
      theme == ReaderTheme.dark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
  Color get textColor =>
      theme == ReaderTheme.dark ? const Color(0xFFE8E6E3) : const Color(0xFF1C1B1F);

  TextStyle get textStyle => TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        letterSpacing: letterSpacing * fontSize,
        color: textColor,
        fontFamily: fontFamily.family,
        fontFamilyFallback: fontFamily.fallback,
      );

  ReaderSettings copyWith({
    ReaderTheme? theme,
    double? fontSize,
    ReaderFont? fontFamily,
    double? lineHeight,
    double? letterSpacing,
    double? paragraphSpacing,
    ViewMode? viewMode,
  }) =>
      ReaderSettings(
        theme: theme ?? this.theme,
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        viewMode: viewMode ?? this.viewMode,
      );

  Map<String, Object> toJson() => {
        'theme': theme.name,
        'fontSize': fontSize,
        'fontFamily': fontFamily.name,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'paragraphSpacing': paragraphSpacing,
        'viewMode': viewMode.name,
      };

  /// Missing or unknown values take the default.
  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    const d = ReaderSettings();
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == json[key]).firstOrNull ?? fallback;
    double number(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    return ReaderSettings(
      theme: pick(ReaderTheme.values, 'theme', d.theme),
      fontSize: number('fontSize', d.fontSize),
      fontFamily: pick(ReaderFont.values, 'fontFamily', d.fontFamily),
      lineHeight: number('lineHeight', d.lineHeight),
      letterSpacing: number('letterSpacing', d.letterSpacing),
      paragraphSpacing: number('paragraphSpacing', d.paragraphSpacing),
      viewMode: pick(ViewMode.values, 'viewMode', d.viewMode),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.theme == theme &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.lineHeight == lineHeight &&
      other.letterSpacing == letterSpacing &&
      other.paragraphSpacing == paragraphSpacing &&
      other.viewMode == viewMode;

  @override
  int get hashCode => Object.hash(
      theme, fontSize, fontFamily, lineHeight, letterSpacing, paragraphSpacing, viewMode);
}

/// Settings are kept on the device.
class ReaderSettingsStore {
  ReaderSettingsStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'reader_settings';

  ReaderSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const ReaderSettings();
    try {
      return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const ReaderSettings();
    }
  }

  Future<void> save(ReaderSettings settings) =>
      _prefs.setString(_key, jsonEncode(settings.toJson()));
}
