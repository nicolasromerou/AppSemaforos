import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'traffic_data.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.repository});

  final TrafficRepository? repository;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  DateTime get _today {
    final now = chileTime(DateTime.now());
    return DateTime.utc(now.year, now.month, now.day);
  }

  late DateTime _end = _today;
  late DateTime _start = _end.subtract(const Duration(days: 6));
  Access? _access;
  int _request = 0;
  TrafficStats? _data;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _data = null;
    });
    try {
      final data = widget.repository == null
          ? TrafficStats.preview(_start, _end, _access)
          : await widget.repository!
                .stats(_start, _end, _access)
                .timeout(const Duration(seconds: 12));
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _selectDates() async {
    final today = _today;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: DateTime(_start.year, _start.month, _start.day),
        end: DateTime(_end.year, _end.month, _end.day),
      ),
      helpText: 'Período de estadísticas',
      saveText: 'Aplicar',
    );
    if (range == null || !mounted) return;
    final start = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime.utc(range.end.year, range.end.month, range.end.day);
    if (end.difference(start).inDays > 92) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona hasta 93 días.')),
      );
      return;
    }
    _start = start;
    _end = end;
    await _load();
  }

  void _preset(int days) {
    _end = _today;
    _start = _end.subtract(Duration(days: days - 1));
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final format = DateFormat('d MMM y', 'es_CL');
    final days = _end.difference(_start).inDays + 1;
    return PageBody(
      refresh: _load,
      children: [
        const PageHeader(
          title: 'Estadísticas',
          subtitle: 'Flujo vehicular del cruce central',
        ),
        const SizedBox(height: 19),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (length, label) in [
                    (1, 'Hoy'),
                    (7, '7 días'),
                    (30, '30 días'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: days == length && _end == _today,
                      onSelected: (_) => _preset(length),
                    ),
                  OutlinedButton.icon(
                    onPressed: _selectDates,
                    icon: const Icon(Icons.date_range_outlined, size: 17),
                    label: const Text('Fechas'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _start == _end
                        ? format.format(_start)
                        : '${format.format(_start)} – ${format.format(_end)}',
                    style: type(
                      13,
                      FontWeight.w700,
                      color: CrucePalette.of(context).secondary,
                    ),
                  ),
                  DropdownButton<Access?>(
                    value: _access,
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todos los accesos'),
                      ),
                      for (final access in Access.values)
                        DropdownMenuItem(
                          value: access,
                          child: Text(access.label),
                        ),
                    ],
                    onChanged: (access) {
                      _access = access;
                      unawaited(_load());
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(),
        if (_failed)
          Notice(
            'No se pudieron cargar las estadísticas.',
            alert: true,
            action: TextButton(
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
        if (data != null) ...[
          _Totals(data),
          const SizedBox(height: 14),
          if (data.total == 0)
            const Notice('No hay conteos de vehículos en este período.'),
          if (data.total > 0) ...[
            _TrafficChart(
              title: data.hourly ? 'Vehículos por hora' : 'Vehículos por día',
              series: data.series,
            ),
            const SizedBox(height: 14),
            _TrafficChart(
              title: 'Perfil por hora del día',
              series: data.profile,
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final access = _Breakdown('Vehículos por acceso', {
                for (final value in Access.values.where(
                  (value) => _access == null || value == _access,
                ))
                  value.label: data.byAccess[value.code] ?? 0,
              });
              final vehicle = _Breakdown('Vehículos por tipo', {
                for (final item in vehicleLabels.entries)
                  item.value: data.byVehicle[item.key] ?? 0,
              });
              if (constraints.maxWidth < 570) {
                return Column(
                  children: [access, const SizedBox(height: 14), vehicle],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: access),
                  const SizedBox(width: 14),
                  Expanded(child: vehicle),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _Breakdown('Cortes de verde', {
            for (final item in data.cuts.entries)
              cutLabels[item.key] ?? item.key: item.value,
          }, subtitle: 'Motivos del cruce completo'),
        ],
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals(this.data);

  final TrafficStats data;

  @override
  Widget build(BuildContext context) {
    final totalCuts = data.cuts.values.fold(0, (sum, count) => sum + count);
    final noDemand = data.cuts['sin_demanda'] ?? 0;
    final percent = totalCuts == 0
        ? '—'
        : '${(100 * noDemand / totalCuts).round()} %';
    return Panel(
      child: Wrap(
        spacing: 30,
        runSpacing: 16,
        children: [
          _Total(number(data.total), 'Vehículos contados'),
          _Total(number(noDemand), 'Cortes sin demanda'),
          _Total(percent, 'De los cortes de verde'),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: figure(36)),
      const SizedBox(height: 4),
      Text(
        label,
        style: type(
          12,
          FontWeight.w700,
          color: CrucePalette.of(context).secondary,
        ),
      ),
    ],
  );
}

class _TrafficChart extends StatelessWidget {
  const _TrafficChart({required this.title, required this.series});

  final String title;
  final List<TrafficInterval> series;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    final palette = CrucePalette.of(context);
    final vehicleColors = palette.isNight
        ? const [Color(0xFFD8F477), Color(0xFF76BD96), Color(0xFFADC6EA)]
        : const [Color(0xFF286748), Color(0xFF76A67F), Color(0xFFC1D8A5)];
    final peak = series.fold(0, (max, item) => math.max(max, item.total));
    final units = math.max(1, (peak / 4).ceil());
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 13,
            runSpacing: 6,
            children: [
              for (final (index, label) in vehicleLabels.values.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Dot(vehicleColors[index]),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: type(
                        11,
                        FontWeight.w700,
                        color: CrucePalette.of(context).secondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                constraints.maxWidth - 41,
                series.length * 8.0,
              );
              final step = math.max(1, (series.length / (width / 66)).ceil());
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    height: 152,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final value in [units * 4, units * 2, 0])
                          FittedBox(
                            child: Text(
                              number(value),
                              style: type(
                                10,
                                FontWeight.w700,
                                color: CrucePalette.of(context).secondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 152,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Divider(height: 1),
                                      Divider(height: 1),
                                      Divider(height: 1),
                                    ],
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final interval in series)
                                        Expanded(
                                          child: _Bar(
                                            interval: interval,
                                            ceiling: units * 4,
                                            vehicleColors: vehicleColors,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < series.length;
                                  index += step
                                )
                                  Expanded(
                                    flex: math.min(step, series.length - index),
                                    child: Text(
                                      series[index].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: type(
                                        9,
                                        FontWeight.w700,
                                        color: CrucePalette.of(
                                          context,
                                        ).secondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.interval,
    required this.ceiling,
    required this.vehicleColors,
  });

  final TrafficInterval interval;
  final int ceiling;
  final List<Color> vehicleColors;

  @override
  Widget build(BuildContext context) => Tooltip(
    triggerMode: TooltipTriggerMode.tap,
    message:
        '${interval.label} · ${number(interval.total)} vehículos\n${number(interval.autos)} autos · ${number(interval.pickups)} camionetas · ${number(interval.buses)} buses',
    child: Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.bottomCenter,
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 54),
          child: SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, value) in [
                    interval.autos,
                    interval.pickups,
                    interval.buses,
                  ].indexed.toList().reversed)
                    SizedBox(
                      height: 152 * value / ceiling,
                      width: double.infinity,
                      child: ColoredBox(color: vehicleColors[index]),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown(this.title, this.entries, {this.subtitle});

  final String title;
  final String? subtitle;
  final Map<String, int> entries;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        if (subtitle != null)
          Text(
            subtitle!,
            style: type(
              12,
              FontWeight.w700,
              color: CrucePalette.of(context).secondary,
            ),
          ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: Text('Sin cortes registrados.'),
          ),
        for (final item in entries.entries) ...[
          const Divider(height: 20),
          Row(
            children: [
              Expanded(child: Text(item.key)),
              Text(number(item.value), style: type(15, FontWeight.w800)),
            ],
          ),
        ],
      ],
    ),
  );
}
