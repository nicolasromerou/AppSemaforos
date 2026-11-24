import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design.dart';
import 'traffic_data.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({
    super.key,
    required this.repository,
    required this.role,
    required this.light,
    required this.onLightChanged,
  });

  final TrafficRepository? repository;
  final Role role;
  final MonitorLight light;
  final ValueChanged<MonitorLight> onLightChanged;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  TrafficState? _state;
  List<PhaseEvent> _events = [];
  String _name = previewName;
  bool _loading = true;
  bool _failed = false;
  bool _eventsFailed = false;
  bool _stale = false;
  bool _eventsDirty = false;
  Future<void>? _stateRequest;
  Future<void>? _eventsRequest;
  Timer? _clock;
  Timer? _poll;
  Timer? _reconnect;
  int _reconnectSeconds = 2;
  AppLifecycleListener? _lifecycle;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository == null) {
      _state = TrafficState.preview(DateTime.now());
      _loading = false;
    } else {
      _subscribe();
      unawaited(_refresh());
      _lifecycle = AppLifecycleListener(
        onResume: () {
          _updateClock();
          unawaited(_refresh());
        },
      );
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_failed || _state == null || _stale) unawaited(_loadState());
      });
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  void _updateClock() {
    final now = DateTime.now();
    final light = MonitorLight.at(now);
    if (widget.light != light) widget.onLightChanged(light);
    if (widget.repository == null) {
      _accept(TrafficState.preview(now));
    } else {
      final stale = _state?.isStale(now) ?? false;
      if (stale != _stale) setState(() => _stale = stale);
    }
  }

  void _subscribe() {
    final client = widget.repository!.client;
    final channel = client.channel(
      'monitoreo:$cruceId:${DateTime.now().microsecondsSinceEpoch}',
    );
    _channel = channel;
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'cruce_id',
      value: cruceId,
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'estado_cruce',
      filter: filter,
      callback: (payload) {
        if (mounted && _channel == channel && payload.newRecord.isNotEmpty) {
          _accept(TrafficState.fromJson(payload.newRecord));
        }
      },
    );
    if (widget.role.isStaff) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'eventos_fase',
        filter: filter,
        callback: (_) => unawaited(_loadEvents()),
      );
    }
    channel.subscribe((status, _) {
      if (!mounted || _channel != channel) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnect?.cancel();
        _reconnect = null;
        _reconnectSeconds = 2;
        unawaited(_refresh());
        return;
      }
      _reconnect ??= Timer(Duration(seconds: _reconnectSeconds), () {
        _reconnect = null;
        if (!mounted || _channel != channel) return;
        _reconnectSeconds = math.min(_reconnectSeconds * 2, 30);
        _channel = null;
        unawaited(client.removeChannel(channel));
        _subscribe();
      });
    });
  }

  void _accept(TrafficState? value) {
    final previous = _state;
    if (previous != null &&
        value != null &&
        previous.receivedAt.isAfter(value.receivedAt)) {
      return;
    }
    setState(() {
      _state = value;
      _loading = false;
      _failed = false;
      _stale = value?.isStale(DateTime.now()) ?? false;
    });
  }

  Future<void> _readState() async {
    final previous = _state;
    try {
      final value = await widget.repository!.readState().timeout(
        const Duration(seconds: 10),
      );
      if (mounted && (value != null || identical(previous, _state))) {
        _accept(value);
      }
    } catch (_) {
      if (mounted && identical(previous, _state)) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _loadState() =>
      _stateRequest ??= _readState().whenComplete(() => _stateRequest = null);

  Future<void> _loadEvents() {
    if (!widget.role.isStaff || widget.repository == null || !mounted) {
      return Future.value();
    }
    _eventsDirty = true;
    return _eventsRequest ??= _readEvents().whenComplete(
      () => _eventsRequest = null,
    );
  }

  Future<void> _readEvents() async {
    while (_eventsDirty && mounted) {
      _eventsDirty = false;
      try {
        final events = await widget.repository!.readEvents().timeout(
          const Duration(seconds: 10),
        );
        if (mounted) {
          setState(() {
            _events = events;
            _eventsFailed = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _eventsFailed = true);
      }
    }
  }

  Future<void> _refresh() async {
    final repository = widget.repository;
    if (repository == null) return;
    await Future.wait([
      _loadState(),
      _loadEvents(),
      repository.crossingName().timeout(const Duration(seconds: 10)).then<void>(
        (name) {
          if (mounted && name != _name) setState(() => _name = name);
        },
        onError: (Object _) {},
      ),
    ]);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    _reconnect?.cancel();
    _lifecycle?.dispose();
    if (_channel case final channel?) {
      unawaited(widget.repository!.client.removeChannel(channel));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final current = _stale ? null : state;
    final demo = widget.repository == null;
    final light = widget.light;
    final status = switch ((demo, _loading, _failed, _stale, state)) {
      (true, _, _, _, _) => 'Simulación',
      (_, true, _, _, _) => 'Conectando',
      (_, _, true, _, _) => 'Sin conexión',
      (_, _, _, true, _) => 'Datos desactualizados',
      (_, _, _, _, null) => 'Sin datos',
      _ => 'En vivo',
    };
    return ColoredBox(
      color: light.background,
      child: PageBody(
        refresh: demo ? null : _refresh,
        children: [
          _MonitorHeading(
            name: _name,
            status: status,
            lastAt: state?.receivedAt,
            light: light,
            refresh: demo ? null : _refresh,
          ),
          const SizedBox(height: 15),
          if (_loading)
            LinearProgressIndicator(minHeight: 2, color: light.accent),
          if (_failed) ...[
            Notice(
              'No se pudo actualizar el cruce.',
              alert: true,
              action: TextButton(
                onPressed: _refresh,
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (current?.fallback == true) ...[
            const Notice(
              'Respaldo a tiempo fijo activo.',
              icon: Icons.warning_amber_rounded,
              alert: true,
            ),
            const SizedBox(height: 10),
          ] else if ((current?.sensorAge ?? 0) > 2) ...[
            const Notice(
              'La detección lleva más de 2 s sin lecturas.',
              icon: Icons.warning_amber_rounded,
              alert: true,
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 710;
              final accesses = _AccessPanel(
                state: current,
                previous: state,
                light: light,
              );
              final diagnostics = state == null
                  ? null
                  : _Diagnostics(state: state, stale: _stale, light: light);
              final diagram = _MonitorMap(state: current, light: light);
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: SizedBox(height: 329, child: diagram),
                        ),
                        const SizedBox(width: 17),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              accesses,
                              if (diagnostics != null) ...[
                                const SizedBox(height: 16),
                                diagnostics,
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Stack(
                          children: [
                            SizedBox(height: 302, child: diagram),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(9, 267, 9, 0),
                              child: accesses,
                            ),
                          ],
                        ),
                        if (diagnostics != null) ...[
                          const SizedBox(height: 16),
                          diagnostics,
                        ],
                      ],
                    );
            },
          ),
          if (widget.role.isStaff && !demo) ...[
            const SizedBox(height: 16),
            _Events(
              events: _events,
              failed: _eventsFailed,
              retry: _loadEvents,
              light: light,
            ),
          ],
        ],
      ),
    );
  }
}

class _MonitorHeading extends StatelessWidget {
  const _MonitorHeading({
    required this.name,
    required this.status,
    required this.lastAt,
    required this.light,
    required this.refresh,
  });

  final String name;
  final String status;
  final DateTime? lastAt;
  final MonitorLight light;
  final VoidCallback? refresh;

  @override
  Widget build(BuildContext context) {
    final caution = status != 'En vivo' && status != 'Simulación';
    final statusColor = caution
        ? (light == MonitorLight.night
              ? signalYellow
              : signalInk(Signal.yellow))
        : light.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: type(
                  31,
                  FontWeight.w800,
                  color: light.foreground,
                  spacing: -1.4,
                  height: 1.08,
                ),
              ),
            ),
            if (refresh != null) ...[
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Actualizar monitoreo',
                onPressed: refresh,
                style: IconButton.styleFrom(
                  foregroundColor: light.foreground,
                  side: BorderSide(color: light.border),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 21),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              lastAt == null
                  ? 'Esperando la primera lectura'
                  : 'Última lectura  ${clock(lastAt!)}',
              style: type(12, FontWeight.w700, color: light.secondary),
            ),
            StatusPill(
              status,
              foreground: statusColor,
              background: Color.alphaBlend(
                statusColor.withValues(alpha: .12),
                light.background,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonitorMap extends StatelessWidget {
  const _MonitorMap({required this.state, required this.light});

  final TrafficState? state;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: light.border),
      gradient: RadialGradient(
        center: const Alignment(-.35, -.45),
        radius: 1.1,
        colors: light == MonitorLight.night
            ? const [Color(0xFF334D3F), Color(0xFF14241E)]
            : const [Color(0xFFD5DDC5), Color(0xFFA4B8A7)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
          child: Text(
            'Plano del cruce',
            style: type(12, FontWeight.w800, color: light.foreground),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 41),
            child: _RoadPlan(state: state, light: light),
          ),
        ),
      ],
    ),
  );
}

class CrossingPanel extends StatelessWidget {
  const CrossingPanel({
    super.key,
    required this.state,
    required this.status,
    required this.wide,
    required this.lastAt,
  });

  final TrafficState? state;
  final String status;
  final bool wide;
  final DateTime? lastAt;

  @override
  Widget build(BuildContext context) {
    final foreground = status == 'En vivo' || status == 'Simulación'
        ? signalGreen
        : signalYellow;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: night,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Plano del cruce',
                    style: type(
                      16,
                      FontWeight.w800,
                      color: Colors.white,
                      spacing: -.3,
                    ),
                  ),
                ),
                StatusPill(
                  status,
                  foreground: foreground,
                  background: const Color(0xFF293A30),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AspectRatio(
              aspectRatio: wide ? 1.65 : 1.38,
              child: _RoadPlan(state: state, light: MonitorLight.night),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 10, 17, 15),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 10,
              runSpacing: 5,
              children: [
                Text(
                  'I-5  /  $cruceId',
                  style: type(11, FontWeight.w700, color: mapText, spacing: .6),
                ),
                Text(
                  lastAt == null
                      ? 'Esperando la primera lectura'
                      : 'Última lectura  ${clock(lastAt!)}',
                  style: type(11, FontWeight.w700, color: mapText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadPlan extends StatelessWidget {
  const _RoadPlan({required this.state, required this.light});

  final TrafficState? state;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Plano esquemático del cruce',
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _CrossingPainter(state, light)),
        ),
        for (final access in Access.values)
          Align(
            alignment: switch (access) {
              Access.north => const Alignment(0, -.94),
              Access.east => const Alignment(.96, 0),
              Access.south => const Alignment(0, .94),
              Access.west => const Alignment(-.96, 0),
            },
            child: _CompassLabel(access),
          ),
      ],
    ),
  );
}

class _CompassLabel extends StatelessWidget {
  const _CompassLabel(this.access);

  final Access access;

  @override
  Widget build(BuildContext context) => Semantics(
    label: access.label,
    excludeSemantics: true,
    child: Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: night,
        border: Border.all(color: const Color(0xFF547061)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        access == Access.west
            ? 'P'
            : access == Access.east
            ? 'O'
            : access.code,
        style: type(10, FontWeight.w800, color: const Color(0xFFE4EEE6)),
      ),
    ),
  );
}

class _CrossingPainter extends CustomPainter {
  const _CrossingPainter(this.state, this.light);

  final TrafficState? state;
  final MonitorLight light;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final lane = math.min(size.width, size.height) * .165;
    final dark = light == MonitorLight.night;
    final paint = Paint();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final xEnd = center.dx - 7;
    final yEnd = center.dy - 7;
    for (final (x, y) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      canvas.save();
      canvas.scale(x.toDouble(), y.toDouble());
      final block = Rect.fromLTRB(lane + 13, lane + 13, xEnd - 4, yEnd - 4);
      if (block.isEmpty) {
        canvas.restore();
        continue;
      }
      final outline = RRect.fromRectAndRadius(block, const Radius.circular(11));
      canvas.drawRRect(
        outline.shift(const Offset(2, 3)),
        paint..color = const Color(0x3214241D),
      );
      canvas.drawRRect(
        outline,
        paint..color = dark ? const Color(0xFF263D31) : const Color(0xFFB7C7AD),
      );
      canvas.drawRRect(
        outline,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark ? const Color(0xFF4B6353) : const Color(0xFFDFE4D0),
      );
      paint.style = PaintingStyle.fill;
      for (var n = 0; n < 4; n++) {
        final spot = Offset(
          block.left + 11 + n * 11,
          block.top + 11 + n % 2 * 6,
        );
        if (!block.deflate(6).contains(spot)) break;
        final radius = n.isEven ? 6.0 : 4.5;
        canvas.drawCircle(
          spot.translate(1.4, 2.6),
          radius,
          paint..color = const Color(0x5511231B),
        );
        canvas.drawCircle(
          spot,
          radius,
          paint
            ..color = dark ? const Color(0xFF456652) : const Color(0xFF668B67),
        );
        canvas.drawCircle(
          spot.translate(-1.5, -1.5),
          radius * .54,
          paint
            ..color = dark ? const Color(0xFF547660) : const Color(0xFF8AA97B),
        );
      }
      if (block.width > 65 && block.height > 34) {
        final roof = RRect.fromRectAndRadius(
          Rect.fromLTRB(
            block.right - 37,
            block.bottom - 23,
            block.right - 7,
            block.bottom - 7,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(
          roof.shift(const Offset(2, 2)),
          paint..color = const Color(0x44142019),
        );
        canvas.drawRRect(
          roof,
          paint
            ..color = dark ? const Color(0xFF405449) : const Color(0xFFD6D8C8),
        );
      }
      canvas.restore();
    }
    final road = Path()
      ..moveTo(-lane, -yEnd)
      ..lineTo(lane, -yEnd)
      ..lineTo(lane, -lane - 9)
      ..quadraticBezierTo(lane, -lane, lane + 9, -lane)
      ..lineTo(xEnd, -lane)
      ..lineTo(xEnd, lane)
      ..lineTo(lane + 9, lane)
      ..quadraticBezierTo(lane, lane, lane, lane + 9)
      ..lineTo(lane, yEnd)
      ..lineTo(-lane, yEnd)
      ..lineTo(-lane, lane + 9)
      ..quadraticBezierTo(-lane, lane, -lane - 9, lane)
      ..lineTo(-xEnd, lane)
      ..lineTo(-xEnd, -lane)
      ..lineTo(-lane - 9, -lane)
      ..quadraticBezierTo(-lane, -lane, -lane, -lane - 9)
      ..close();
    canvas.drawShadow(road, const Color(0xAA102219), 7, false);
    canvas.drawPath(
      road,
      paint
        ..shader = ui.Gradient.linear(
          Offset(-xEnd, -yEnd),
          Offset(xEnd, yEnd),
          dark
              ? const [Color(0xFF333E39), Color(0xFF222E29)]
              : const [Color(0xFF5F6B65), Color(0xFF43534D)],
        ),
    );
    paint.shader = null;
    canvas.drawPath(
      road,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = dark ? const Color(0xFF667B6E) : const Color(0xFFDDE1D0),
    );
    paint.style = PaintingStyle.fill;
    for (final access in Access.values) {
      canvas.save();
      canvas.rotate(access.index * math.pi / 2);
      final end = access.index.isEven ? yEnd : xEnd;
      for (var offset = lane + 18; offset < end - 8; offset += 12) {
        canvas.drawLine(
          Offset(0, -offset),
          Offset(0, -offset - 5),
          paint
            ..strokeWidth = 1.2
            ..color = const Color(0xFFC0AA75),
        );
      }
      for (final edge in [-1, 1]) {
        final x = (lane - 4) * edge;
        if (end > lane + 18) {
          canvas.drawLine(
            Offset(x, -lane - 13),
            Offset(x, -end + 3),
            paint
              ..strokeWidth = .85
              ..color = const Color(0x778E9F97),
          );
        }
      }
      for (var stripe = -3; stripe <= 3; stripe++) {
        final x = stripe * lane / 4;
        canvas.drawRect(
          Rect.fromLTWH(x - 1.5, -lane - 9, 3, 7),
          paint..color = const Color(0xFF8D9D91),
        );
      }
      final signal = state?.signal(access) ?? Signal.unknown;
      final color = signalLight(signal);
      final stop = Offset(-lane - 5, -lane - 7);
      if (signal != Signal.unknown) {
        canvas.drawCircle(
          stop,
          12,
          paint..color = color.withValues(alpha: .18),
        );
      }
      canvas.drawCircle(stop, 8.5, paint..color = night);
      canvas.drawCircle(stop, 4.6, paint..color = color);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrossingPainter oldDelegate) =>
      oldDelegate.light != light ||
      Access.values.any(
        (access) => oldDelegate.state?.signal(access) != state?.signal(access),
      );
}

class _AccessPanel extends StatelessWidget {
  const _AccessPanel({
    required this.state,
    required this.previous,
    required this.light,
  });

  final TrafficState? state;
  final TrafficState? previous;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) {
    final total = previous?.counts.fold(0, (sum, count) => sum + count);
    final dark = light == MonitorLight.night;
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      key: const ValueKey('access-panel'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10271C).withValues(alpha: dark ? .29 : .12),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: light.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    light.panel,
                    light.border,
                    .27,
                  )!.withValues(alpha: .89),
                  light.panel.withValues(alpha: .97),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        total == null ? '—' : number(total),
                        style: figure(46, color: light.foreground),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        state == null && previous != null
                            ? 'Vehículos detectados\nen la última lectura'
                            : 'Vehículos detectados',
                        style: type(
                          13,
                          FontWeight.w700,
                          color: light.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Por acceso',
                  style: type(13, FontWeight.w800, color: light.foreground),
                ),
                const SizedBox(height: 5),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final twoColumns = constraints.maxWidth >= 234 * textScale;
                    final tileWidth = twoColumns
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final access in Access.values)
                          SizedBox(
                            width: tileWidth,
                            child: _AccessTile(
                              access: access,
                              signal: state?.signal(access) ?? Signal.unknown,
                              count: previous?.counts[access.index],
                              light: light,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessTile extends StatelessWidget {
  const _AccessTile({
    required this.access,
    required this.signal,
    required this.count,
    required this.light,
  });

  final Access access;
  final Signal signal;
  final int? count;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: light.background.withValues(alpha: .40),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                access.label,
                style: type(13, FontWeight.w800, color: light.foreground),
              ),
              Row(
                children: [
                  Dot(
                    light == MonitorLight.night
                        ? signalLight(signal)
                        : signalInk(signal),
                    size: 5,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      signal.label,
                      style: type(11, FontWeight.w700, color: light.secondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            count == null ? '—' : number(count!),
            textAlign: TextAlign.right,
            style: figure(21, color: light.foreground),
          ),
        ),
      ],
    ),
  );
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({
    required this.state,
    required this.stale,
    required this.light,
  });

  final TrafficState state;
  final bool stale;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Panel(
    light: light,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          stale ? 'Última lectura del controlador' : 'Controlador',
          color: light.foreground,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Diagnostic('Modo activo', modeLabel(state.runningMode), light),
            if (state.mode != state.runningMode)
              _Diagnostic('Modo solicitado', modeLabel(state.mode), light),
            _Diagnostic('Etapa', stageLabel(state.stage), light),
            _Diagnostic(
              'Edad de la detección',
              '${state.sensorAge.toStringAsFixed(1).replaceAll('.', ',')} s',
              light,
            ),
          ],
        ),
        if (state.reason case final reason? when reason.trim().isNotEmpty) ...[
          const SizedBox(height: 11),
          Text(
            reason,
            style: type(13, FontWeight.w700, color: light.secondary),
          ),
        ],
      ],
    ),
  );
}

class _Diagnostic extends StatelessWidget {
  const _Diagnostic(this.label, this.value, this.light);

  final String label;
  final String value;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: type(11, FontWeight.w700, color: light.secondary)),
      const SizedBox(height: 3),
      Text(value, style: type(15, FontWeight.w800, color: light.foreground)),
    ],
  );
}

class _Events extends StatelessWidget {
  const _Events({
    required this.events,
    required this.failed,
    required this.retry,
    required this.light,
  });

  final List<PhaseEvent> events;
  final bool failed;
  final VoidCallback retry;
  final MonitorLight light;

  @override
  Widget build(BuildContext context) => Panel(
    light: light,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Cambios de fase', color: light.foreground),
        if (failed)
          TextButton(
            onPressed: retry,
            style: TextButton.styleFrom(foregroundColor: light.accent),
            child: const Text('Reintentar la carga de eventos'),
          ),
        if (events.isEmpty && !failed)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              'Sin cambios registrados.',
              style: type(13, FontWeight.w600, color: light.secondary),
            ),
          ),
        for (final event in events) ...[
          Divider(height: 17, color: light.border),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    stageLabel(event.stage),
                    if (event.active.isNotEmpty)
                      Access.values
                          .where((access) => event.active.contains(access.code))
                          .map((access) => access.label)
                          .join(' / '),
                    if (event.reason != null)
                      cutLabels[event.reason] ?? event.reason!,
                  ].join(' · '),
                  style: type(13, FontWeight.w700, color: light.foreground),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateTimeLabel(event.at),
                style: type(11, FontWeight.w700, color: light.secondary),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
