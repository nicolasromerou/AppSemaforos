import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design.dart';
import 'traffic_data.dart';

class IncidentsPage extends StatefulWidget {
  const IncidentsPage({
    super.key,
    required this.repository,
    required this.userId,
    required this.role,
  });

  final TrafficRepository? repository;
  final String? userId;
  final Role role;

  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  List<Incident> _rows = [];
  bool _loading = true;
  bool _failed = false;
  bool _dirty = false;
  bool _showAll = false;
  Future<void>? _request;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository == null) {
      _loading = false;
      _rows = [
        Incident(
          'demo-2',
          'intermitente',
          'La luz del acceso oriente parpadea de forma irregular.',
          'en_revision',
          DateTime.now().subtract(const Duration(days: 1)),
          null,
        ),
        Incident(
          'demo-1',
          'luz_apagada',
          'La luz del acceso sur no encendió durante el ciclo.',
          'resuelta',
          DateTime.now().subtract(const Duration(days: 4)),
          null,
        ),
      ];
    } else {
      _channel = repository.client
          .channel('flutter-incidents-${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'incidencias',
            filter: widget.role == Role.operator
                ? null
                : PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'autor_id',
                    value: widget.userId!,
                  ),
            callback: (_) => unawaited(_load()),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(_load());
            }
          });
      unawaited(_load());
    }
  }

  Future<void> _load() {
    if (!mounted || widget.repository == null) return Future.value();
    _dirty = true;
    return _request ??= _read().whenComplete(() => _request = null);
  }

  Future<void> _read() async {
    while (_dirty && mounted) {
      _dirty = false;
      final showAll = _showAll;
      try {
        final rows = await widget.repository!
            .incidents(showAll ? null : widget.userId!)
            .timeout(const Duration(seconds: 12));
        if (!mounted) return;
        if (showAll != _showAll) continue;
        setState(() {
          _rows = rows;
          _loading = false;
          _failed = false;
        });
      } catch (_) {
        if (!mounted) return;
        if (showAll != _showAll) continue;
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _show(bool showAll) {
    if (showAll == _showAll) return;
    setState(() {
      _showAll = showAll;
      _rows = [];
      _loading = true;
      _failed = false;
    });
    unawaited(_load());
  }

  Future<void> _report() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReportPage(repository: widget.repository!, userId: widget.userId!),
      ),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Incidencia enviada.')));
    await _load();
  }

  @override
  void dispose() {
    if (_channel case final channel?) {
      unawaited(widget.repository!.client.removeChannel(channel));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return PageBody(
      refresh: repository == null ? null : _load,
      children: [
        PageHeader(
          title: 'Incidencias',
          subtitle: _showAll ? 'Reportes del cruce' : 'Mis reportes del cruce',
          trailing: repository == null
              ? null
              : IconButton(
                  tooltip: 'Actualizar incidencias',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
        ),
        const SizedBox(height: 18),
        if (repository != null && widget.role == Role.operator) ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Mis reportes'),
                selected: !_showAll,
                onSelected: (_) => _show(false),
              ),
              ChoiceChip(
                label: const Text('Todos'),
                selected: _showAll,
                onSelected: (_) => _show(true),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (repository != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _report,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo reporte'),
            ),
          ),
          const SizedBox(height: 15),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (_failed) ...[
          Notice(
            'No se pudieron actualizar los reportes.',
            alert: true,
            action: TextButton(
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_rows.isEmpty && !_loading && !_failed)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inbox_outlined, color: moss, size: 28),
                const SizedBox(height: 9),
                SectionTitle(
                  _showAll ? 'Aún no hay reportes' : 'Aún no tienes reportes',
                ),
              ],
            ),
          ),
        for (final row in _rows) ...[
          _IncidentTile(
            row,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IncidentDetail(
                  incident: row,
                  repository: repository,
                  role: widget.role,
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile(this.incident, {required this.onTap});

  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        incidentTypes[incident.type] ?? incident.type,
                        style: type(16, FontWeight.w800),
                      ),
                      _IncidentBadge(incident.state),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    incident.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type(13, FontWeight.w600, color: muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateTimeLabel(incident.createdAt),
                    style: type(11, FontWeight.w700, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            const Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    ),
  );
}

class _IncidentBadge extends StatelessWidget {
  const _IncidentBadge(this.state);

  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'resuelta' => Signal.green,
      'en_revision' => Signal.yellow,
      _ => Signal.unknown,
    };
    return StatusPill(
      incidentStates[state] ?? state,
      foreground: signalInk(color),
      background: signalSurface(color),
    );
  }
}

class IncidentDetail extends StatefulWidget {
  const IncidentDetail({
    super.key,
    required this.incident,
    required this.repository,
    required this.role,
  });

  final Incident incident;
  final TrafficRepository? repository;
  final Role role;

  @override
  State<IncidentDetail> createState() => _IncidentDetailState();
}

class _IncidentDetailState extends State<IncidentDetail> {
  late Incident _incident = widget.incident;
  late Future<List<IncidentChange>> _history = _getHistory();
  late Future<String>? _photo = _getPhoto();
  RealtimeChannel? _channel;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository == null) return;
    _channel = repository.client
        .channel(
          'flutter-incident-${widget.incident.id}-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'incidencias',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.incident.id,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            setState(() {
              final updated = Incident.fromJson(payload.newRecord);
              final photoChanged = updated.photoPath != _incident.photoPath;
              _incident = updated;
              if (photoChanged) _photo = _getPhoto();
              _history = _getHistory();
            });
          },
        )
        .subscribe((status, _) {
          if (mounted && status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_reload());
          }
        });
  }

  Future<void> _change(String state) async {
    if (_changing) return;
    final closing = state == 'resuelta';
    var note = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final error = incidentNoteError(note, closing: closing);
          return AlertDialog(
            title: Text(closing ? 'Resolver incidencia' : 'Marcar en revisión'),
            content: TextField(
              decoration: InputDecoration(
                labelText: closing ? 'Nota de cierre' : 'Nota opcional',
                counterText: '${note.runes.length} / $incidentNoteLimit',
                errorText: note.isEmpty ? null : error,
              ),
              maxLength: incidentNoteLimit,
              maxLines: 3,
              onChanged: (value) => update(() => note = value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: error != null
                    ? null
                    : () => Navigator.pop(dialogContext, note),
                child: Text(closing ? 'Resolver' : 'Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null || _changing) return;
    setState(() => _changing = true);
    try {
      await widget.repository!.changeIncident(
        _incident.id,
        state,
        result.isEmpty ? null : result,
      );
    } catch (error) {
      if (mounted) {
        final message = switch (error) {
          FormatException(:final message) => message,
          PostgrestException(:final code, :final message)
              when code == '22023' || code == 'P0002' =>
            message,
          _ => 'No se pudo cambiar el estado de la incidencia.',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      await _reload();
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<List<IncidentChange>> _getHistory() {
    final repository = widget.repository;
    return repository == null
        ? Future.value([
            IncidentChange(
              _incident.state,
              null,
              _incident.createdAt.add(const Duration(hours: 4)),
            ),
          ])
        : repository.history(_incident.id).timeout(const Duration(seconds: 12));
  }

  Future<String>? _getPhoto() {
    final path = _incident.photoPath;
    return path == null
        ? null
        : widget.repository
              ?.photoUrl(path)
              .timeout(const Duration(seconds: 12));
  }

  Future<void> _reload() async {
    final repository = widget.repository;
    if (repository == null) return;
    try {
      final updated = await repository
          .incident(_incident.id)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        if (updated != null) _incident = updated;
        _photo = _getPhoto();
        _history = _getHistory();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el reporte.')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_channel case final channel?) {
      unawaited(widget.repository!.client.removeChannel(channel));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Detalle del reporte'),
      actions: [
        if (widget.repository != null)
          IconButton(
            onPressed: _reload,
            tooltip: 'Actualizar reporte',
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    ),
    body: PageBody(
      children: [
        PageHeader(
          title: incidentTypes[_incident.type] ?? _incident.type,
          subtitle: dateTimeLabel(_incident.createdAt),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IncidentBadge(_incident.state),
              const SizedBox(height: 12),
              Text(_incident.description, style: type(16, FontWeight.w600)),
              if (_photo case final photo?) ...[
                const SizedBox(height: 15),
                FutureBuilder<String>(
                  future: photo,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    if (!snapshot.hasData) {
                      return const Notice('La foto no está disponible.');
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        snapshot.data!,
                        width: double.infinity,
                        height: 240,
                        fit: BoxFit.contain,
                        semanticLabel: 'Foto adjunta al reporte',
                        errorBuilder: (context, error, stack) => Notice(
                          'No se pudo mostrar la foto.',
                          action: TextButton(
                            onPressed: () =>
                                setState(() => _photo = _getPhoto()),
                            child: const Text('Reintentar'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (widget.role == Role.operator &&
                  widget.repository != null &&
                  _incident.state != 'resuelta') ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    if (_incident.state == 'recibida')
                      OutlinedButton(
                        onPressed: _changing
                            ? null
                            : () => _change('en_revision'),
                        child: const Text('Marcar en revisión'),
                      ),
                    FilledButton(
                      onPressed: _changing ? null : () => _change('resuelta'),
                      child: const Text('Resolver'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Historial'),
              const SizedBox(height: 11),
              _HistoryRow(
                IncidentChange('recibida', null, _incident.createdAt),
              ),
              FutureBuilder<List<IncidentChange>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(() => _history = _getHistory()),
                      child: const Text('Reintentar el historial'),
                    );
                  }
                  return Column(
                    children: [
                      for (final change
                          in snapshot.data ?? <IncidentChange>[]) ...[
                        const Divider(height: 18),
                        _HistoryRow(change),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.change);

  final IncidentChange change;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Dot(moss, size: 6),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incidentStates[change.state] ?? change.state,
              style: type(13, FontWeight.w800),
            ),
            if (change.note case final note? when note.isNotEmpty) Text(note),
            if (change.responsible case final name?)
              Text(name, style: type(11, FontWeight.w600, color: muted)),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        dateTimeLabel(change.at),
        style: type(11, FontWeight.w700, color: muted),
      ),
    ],
  );
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.repository, required this.userId});

  final TrafficRepository repository;
  final String userId;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  String? _type;
  IncidentPhoto? _photo;
  String? _error;
  bool _busy = false;
  bool _picking = false;

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (picked == null) return;
      if (await picked.length() > 5 * 1024 * 1024) {
        throw const FormatException('La foto supera los 5 MB.');
      }
      final photo = IncidentPhoto.fromBytes(await picked.readAsBytes());
      if (mounted) setState(() => _photo = photo);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la foto.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _picking || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.report(
        user: widget.userId,
        type: _type!,
        description: _description.text.trim(),
        photo: _photo,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'P0001'
              ? 'Alcanzaste el límite de 5 reportes en 24 horas.'
              : 'No se pudo confirmar el envío. Revisa Mis reportes antes de volver a enviarlo.',
        );
      }
    } on StorageException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == '403'
              ? 'No se pudo adjuntar la foto. El límite es de 5 fotos por cuenta en 24 horas.'
              : 'No se pudo adjuntar la foto. Intenta de nuevo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el envío. Revisa Mis reportes antes de volver a enviarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Nuevo reporte')),
      body: PageBody(
        children: [
          const PageHeader(title: 'Reportar incidencia', subtitle: previewName),
          const SizedBox(height: 16),
          Panel(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de incidencia',
                    ),
                    items: [
                      for (final type in incidentTypes.entries)
                        DropdownMenuItem(
                          value: type.key,
                          child: Text(type.value),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _type = value),
                    validator: (value) =>
                        value == null ? 'Selecciona un tipo.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        switch ((value ?? '').trim().runes.length) {
                          < 5 => 'Escribe al menos 5 caracteres.',
                          > 1000 => 'Escribe hasta 1000 caracteres.',
                          _ => null,
                        },
                  ),
                  const SizedBox(height: 10),
                  if (_photo case final photo?) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        photo.bytes,
                        height: 150,
                        fit: BoxFit.contain,
                        semanticLabel: 'Vista previa de la foto',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _photo = null),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Quitar foto'),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      onPressed: _busy || _picking ? null : _pick,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Adjuntar foto'),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Opcional · JPEG, PNG o WebP · hasta 5 MB',
                      style: type(11, FontWeight.w700, color: muted),
                    ),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Notice(error, alert: true),
                  ],
                  const SizedBox(height: 17),
                  FilledButton(
                    onPressed: _busy || _picking ? null : _submit,
                    child: Text(_busy ? 'Enviando…' : 'Enviar reporte'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
