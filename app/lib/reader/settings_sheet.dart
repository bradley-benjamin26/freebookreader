import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/common.dart';
import 'reader_settings.dart';

/// Display settings: theme, font size and style, spacing, page-turner or
/// scroll. Changes apply at once; Escape or the close button closes it.
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key, required this.settings});

  final ValueNotifier<ReaderSettings> settings;

  void _change(ReaderSettings Function(ReaderSettings) update) =>
      settings.value = update(settings.value);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder<ReaderSettings>(
          valueListenable: settings,
          builder: (context, s, _) {
            Widget label(String name) => Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(name, style: text.titleSmall),
                );
            Widget choices<T>(List<(Key, String, T)> options, T selected, ValueChanged<T> onSelect) =>
                Wrap(spacing: 8, children: [
                  for (final (key, name, value) in options)
                    ChoiceChip(
                      key: key,
                      label: Text(name),
                      selected: value == selected,
                      onSelected: (_) => onSelect(value),
                    ),
                ]);
            Widget slider(Key key, String name, double value, double max, int divisions, double min,
                    ValueChanged<double> onChanged) =>
                MergeSemantics(
                  key: key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label(name),
                      Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
                    ],
                  ),
                );

            return SingleChildScrollView(
              key: const Key('reader-settings'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Heading('Display settings', style: text.titleLarge)),
                      IconButton(
                        key: const Key('settings-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, semanticLabel: 'Close settings'),
                      ),
                    ],
                  ),
                  label('Text size'),
                  Row(
                    children: [
                      OutlinedButton(
                        key: const Key('font-decrease'),
                        onPressed: s.fontSize <= ReaderSettings.minFontSize
                            ? null
                            : () => _change((v) =>
                                v.copyWith(fontSize: v.fontSize - ReaderSettings.fontSizeStep)),
                        child: const Icon(Icons.text_decrease, semanticLabel: 'Smaller text'),
                      ),
                      Expanded(
                        child: Semantics(
                          key: const Key('font-size-value'),
                          container: true,
                          label: 'Text size',
                          child: Text(s.fontSize.round().toString(),
                              textAlign: TextAlign.center, style: text.titleMedium),
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('font-increase'),
                        onPressed: s.fontSize >= ReaderSettings.maxFontSize
                            ? null
                            : () => _change((v) =>
                                v.copyWith(fontSize: v.fontSize + ReaderSettings.fontSizeStep)),
                        child: const Icon(Icons.text_increase, semanticLabel: 'Larger text'),
                      ),
                    ],
                  ),
                  label('Font'),
                  choices([
                    for (final font in ReaderFont.values) (Key('font-${font.name}'), font.label, font),
                  ], s.fontFamily, (f) => _change((v) => v.copyWith(fontFamily: f))),
                  label('Colors'),
                  choices([
                    (const Key('theme-light'), 'Light', ReaderTheme.light),
                    (const Key('theme-dark'), 'Dark', ReaderTheme.dark),
                  ], s.theme, (t) => _change((v) => v.copyWith(theme: t))),
                  label('View'),
                  choices([
                    (const Key('view-page-turner'), 'Pages', ViewMode.pageTurner),
                    (const Key('view-scroll'), 'Scroll', ViewMode.scroll),
                  ], s.viewMode, (m) => _change((v) => v.copyWith(viewMode: m))),
                  slider(const Key('setting-line-height'), 'Line spacing', s.lineHeight,
                      ReaderSettings.maxLineHeight, 15, ReaderSettings.minLineHeight,
                      (x) => _change((v) => v.copyWith(lineHeight: x))),
                  slider(const Key('setting-letter-spacing'), 'Letter spacing', s.letterSpacing,
                      ReaderSettings.maxLetterSpacing, 10, 0,
                      (x) => _change((v) => v.copyWith(letterSpacing: x))),
                  slider(const Key('setting-paragraph-spacing'), 'Paragraph spacing',
                      s.paragraphSpacing, ReaderSettings.maxParagraphSpacing, 12, 0,
                      (x) => _change((v) => v.copyWith(paragraphSpacing: x))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
