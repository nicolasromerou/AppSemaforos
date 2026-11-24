import 'package:flutter/material.dart';

import 'traffic_data.dart';

const paper = Color(0xFFF2F4EE);
const surface = Color(0xFFFCFDF8);
const ink = Color(0xFF17231D);
const muted = Color(0xFF56635B);
const line = Color(0xFFDCE3D9);
const moss = Color(0xFF1B563B);
const lime = Color(0xFFD8F477);
const night = Color(0xFF182520);
const mapText = Color(0xFFB9CAC0);
const signalGreen = Color(0xFFC4F36E);
const signalYellow = Color(0xFFFFD474);
const signalRed = Color(0xFFFF9689);

enum MonitorLight {
  day(
    background: Color(0xFFE4EAE0),
    foreground: Color(0xFF172C23),
    secondary: Color(0xFF40574B),
    panel: Color(0xFFF5F8F0),
    border: Color(0xFFBCCDBF),
    accent: Color(0xFF286143),
  ),
  night(
    background: Color(0xFF101D19),
    foreground: Color(0xFFEDF4EB),
    secondary: Color(0xFFB4C8BE),
    panel: Color(0xFF233B31),
    border: Color(0xFF496759),
    accent: Color(0xFFD8F477),
  );

  const MonitorLight({
    required this.background,
    required this.foreground,
    required this.secondary,
    required this.panel,
    required this.border,
    required this.accent,
  });

  final Color background;
  final Color foreground;
  final Color secondary;
  final Color panel;
  final Color border;
  final Color accent;

  static MonitorLight at(DateTime time) {
    final hour = chileTime(time).hour;
    return hour >= 7 && hour < 20 ? day : night;
  }
}

ThemeData appTheme() {
  final colors = ColorScheme.fromSeed(seedColor: moss).copyWith(
    primary: moss,
    onPrimary: Colors.white,
    surface: surface,
    onSurface: ink,
    outline: line,
    error: const Color(0xFFA1262F),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: paper,
    fontFamily: 'Manrope',
    dividerColor: line,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: const Color(0xFFE3EDDB),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(type(11, FontWeight.w700)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
        textStyle: type(14, FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
    ),
  );
}

TextStyle type(
  double size,
  FontWeight weight, {
  Color color = ink,
  double? spacing,
  double? height,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
  letterSpacing: spacing,
  height: height,
);

TextStyle figure(double size, {Color color = ink}) => type(
  size,
  FontWeight.w800,
  color: color,
  spacing: -size * .055,
  height: 1.03,
).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 37});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: night,
      borderRadius: BorderRadius.circular(size * .29),
    ),
    child: Image.asset(
      'assets/brand/cruce-symbol.png',
      excludeFromSemantics: true,
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.color = ink});

  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Mark(),
      const SizedBox(width: 10),
      Text(
        'Cruce',
        style: type(22, FontWeight.w800, color: color, spacing: -1.05),
      ),
    ],
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(19),
    this.light,
  });

  final Widget child;
  final EdgeInsets padding;
  final MonitorLight? light;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: light?.panel ?? surface,
      border: Border.all(color: light?.border ?? line),
      borderRadius: BorderRadius.circular(19),
    ),
    child: child,
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: type(38, FontWeight.w800, spacing: -2.1, height: 1.06),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(subtitle!, style: type(14, FontWeight.w600, color: muted)),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.label, {super.key, this.color = ink});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: type(19, FontWeight.w800, color: color, spacing: -.55),
  );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.foreground = moss,
    this.background = const Color(0xFFE7F0E3),
    this.dot = true,
  });

  final String label;
  final Color foreground;
  final Color background;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[Dot(foreground, size: 6), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            style: type(11, FontWeight.w800, color: foreground),
          ),
        ),
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(
    this.message, {
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.alert = false,
    this.action,
  });

  final String message;
  final IconData icon;
  final bool alert;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = alert ? const Color(0xFF774415) : muted;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFFFF2D9) : const Color(0xFFEAF0E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: type(13, FontWeight.w700, color: color),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.refresh});

  final List<Widget> children;
  final Future<void> Function()? refresh;

  @override
  Widget build(BuildContext context) {
    final content = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  19,
                  MediaQuery.sizeOf(context).width >= 800 ? 29 : 16,
                  19,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return refresh == null
        ? content
        : RefreshIndicator(onRefresh: refresh!, child: content);
  }
}

Color signalInk(Signal signal) => switch (signal) {
  Signal.green => moss,
  Signal.yellow => const Color(0xFF805013),
  Signal.red => const Color(0xFFA33632),
  Signal.unknown => muted,
};

Color signalLight(Signal signal) => switch (signal) {
  Signal.green => signalGreen,
  Signal.yellow => signalYellow,
  Signal.red => signalRed,
  Signal.unknown => const Color(0xFF91A299),
};

Color signalSurface(Signal signal) => switch (signal) {
  Signal.green => const Color(0xFFE7F0DF),
  Signal.yellow => const Color(0xFFFFF0D4),
  Signal.red => const Color(0xFFF9E8E3),
  Signal.unknown => const Color(0xFFE9EDE7),
};
