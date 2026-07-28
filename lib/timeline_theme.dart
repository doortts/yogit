import 'package:flutter/material.dart';

enum TimelineThemeKind {
  systemGraphite('systemGraphite', 'System Graphite', 'Balanced neutral gray'),
  warmGraphite('warmGraphite', 'Warm Graphite', 'Softer, warmer graphite'),
  carbon('carbon', 'Carbon', 'Deep neutral contrast');

  const TimelineThemeKind(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static TimelineThemeKind parse(Object? value) => values.firstWhere(
    (theme) => theme.storageValue == value,
    orElse: () => systemGraphite,
  );

  TimelineThemePalette get palette => switch (this) {
    systemGraphite => TimelineThemePalette.systemGraphite,
    warmGraphite => TimelineThemePalette.warmGraphite,
    carbon => TimelineThemePalette.carbon,
  };
}

@immutable
class TimelineThemePalette extends ThemeExtension<TimelineThemePalette> {
  const TimelineThemePalette({
    required this.background,
    required this.surface,
    required this.panel,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.neutralChip,
    required this.selectedRow,
    required this.interactive,
  });

  static const systemGraphite = TimelineThemePalette(
    background: Color(0xFF1C1C1E),
    surface: Color(0xFF242426),
    panel: Color(0xFF202022),
    raised: Color(0xFF2C2C2E),
    border: Color(0xFF38383A),
    text: Color(0xFFF2F2F7),
    muted: Color(0xFFAEAEB2),
    neutralChip: Color(0xFF2C2C2E),
    selectedRow: Color(0xFF234D72),
    interactive: Color(0xFF0A84FF),
  );

  static const warmGraphite = TimelineThemePalette(
    background: Color(0xFF1D1C1B),
    surface: Color(0xFF282624),
    panel: Color(0xFF232220),
    raised: Color(0xFF302E2B),
    border: Color(0xFF403E3A),
    text: Color(0xFFF3F1EE),
    muted: Color(0xFFB4B0AA),
    neutralChip: Color(0xFF302E2B),
    selectedRow: Color(0xFF44413C),
    interactive: Color(0xFFFF9F0A),
  );

  static const carbon = TimelineThemePalette(
    background: Color(0xFF121213),
    surface: Color(0xFF1C1C1E),
    panel: Color(0xFF181819),
    raised: Color(0xFF272729),
    border: Color(0xFF303033),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFFB8B8BD),
    neutralChip: Color(0xFF272729),
    selectedRow: Color(0xFF38383B),
    interactive: Color(0xFF64D2FF),
  );

  final Color background;
  final Color surface;
  final Color panel;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color neutralChip;
  final Color selectedRow;
  final Color interactive;

  static TimelineThemePalette of(BuildContext context) =>
      Theme.of(context).extension<TimelineThemePalette>() ?? systemGraphite;

  @override
  TimelineThemePalette copyWith({
    Color? background,
    Color? surface,
    Color? panel,
    Color? raised,
    Color? border,
    Color? text,
    Color? muted,
    Color? neutralChip,
    Color? selectedRow,
    Color? interactive,
  }) => TimelineThemePalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    panel: panel ?? this.panel,
    raised: raised ?? this.raised,
    border: border ?? this.border,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    neutralChip: neutralChip ?? this.neutralChip,
    selectedRow: selectedRow ?? this.selectedRow,
    interactive: interactive ?? this.interactive,
  );

  @override
  TimelineThemePalette lerp(covariant TimelineThemePalette? other, double t) {
    if (other == null) return this;
    return TimelineThemePalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      neutralChip: Color.lerp(neutralChip, other.neutralChip, t)!,
      selectedRow: Color.lerp(selectedRow, other.selectedRow, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineThemePalette &&
      background == other.background &&
      surface == other.surface &&
      panel == other.panel &&
      raised == other.raised &&
      border == other.border &&
      text == other.text &&
      muted == other.muted &&
      neutralChip == other.neutralChip &&
      selectedRow == other.selectedRow &&
      interactive == other.interactive;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    panel,
    raised,
    border,
    text,
    muted,
    neutralChip,
    selectedRow,
    interactive,
  );
}

extension TimelineThemeContext on BuildContext {
  TimelineThemePalette get timelineTheme => TimelineThemePalette.of(this);
}

ThemeData timelineThemeData(ThemeData base, TimelineThemeKind kind) {
  final palette = kind.palette;
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: base.colorScheme.copyWith(
      surface: palette.surface,
      primary: palette.interactive,
    ),
    extensions: [
      ...base.extensions.values.where(
        (extension) => extension is! TimelineThemePalette,
      ),
      palette,
    ],
  );
}
