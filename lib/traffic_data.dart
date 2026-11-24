import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'backend_connection.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const accountUrl = String.fromEnvironment(
  'ACCOUNT_URL',
  defaultValue: 'https://control-semaforos.vercel.app/api/cuenta',
);
const demoMode = bool.fromEnvironment('DEMO');
const cruceId = 'maqueta-01';
const previewName = 'Cruce de la maqueta 3D';

final chile = tz.getLocation('America/Santiago');
DateTime chileTime(DateTime date) => tz.TZDateTime.from(date, chile);
String clock(DateTime date) => DateFormat('HH:mm:ss').format(chileTime(date));
String dateTimeLabel(DateTime date) =>
    DateFormat('d MMM · HH:mm', 'es_CL').format(chileTime(date));
String number(int value) => NumberFormat.decimalPattern('es_CL').format(value);
String isoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

enum Access {
  north('N', 'Norte'),
  east('E', 'Oriente'),
  south('S', 'Sur'),
  west('W', 'Poniente');

  const Access(this.code, this.label);
  final String code;
  final String label;
}

enum Signal {
  green('Verde'),
  yellow('Amarillo'),
  red('Rojo'),
  unknown('Sin señal');

  const Signal(this.label);
  final String label;
}

enum Role {
  citizen('Ciudadano'),
  operator('Operador'),
  analyst('Analista');

  const Role(this.label);
  final String label;

  bool get isStaff => this != citizen;

  static Role fromCode(String? code) => switch (code) {
    'operador' => operator,
    'analista' => analyst,
    _ => citizen,
  };
}

String modeLabel(String mode) => switch (mode) {
  'adaptive' => 'Adaptativo',
  'fixed' => 'Tiempo fijo',
  'fti' => 'FTI por demanda',
  _ => mode,
};

String stageLabel(String stage) => switch (stage) {
  'GREEN' => 'Verde',
  'YELLOW' => 'Amarillo',
  'ALL_RED' => 'Todo rojo',
  _ => 'Sin señal',
};

const cutLabels = {
  'sin_demanda': 'Sin demanda',
  'verde_maximo': 'Verde máximo',
  'tiempo_fijo': 'Tiempo fijo',
  'balance_colas': 'Balance de colas',
  'prioridad': 'Prioridad',
  'cambio_modo': 'Cambio de modo',
  'sin_motivo': 'Sin motivo informado',
};
const vehicleLabels = {
  'auto': 'Autos',
  'camioneta': 'Camionetas',
  'bus': 'Buses',
};
const incidentTypes = {
  'luz_apagada': 'Luz apagada',
  'intermitente': 'Intermitente',
  'tiempo_anomalo': 'Tiempo anómalo',
  'dano_fisico': 'Daño físico',
  'otro': 'Otro',
};
const incidentStates = {
  'recibida': 'Recibida',
  'en_revision': 'En revisión',
  'resuelta': 'Resuelta',
};

const incidentNoteLimit = 1000;

String? incidentNoteError(String? note, {required bool closing}) {
  final text = note?.trim() ?? '';
  if (closing && text.isEmpty) return 'Escribe una nota de cierre.';
  if (text.runes.length > incidentNoteLimit) {
    return 'La nota debe tener hasta $incidentNoteLimit caracteres.';
  }
  return null;
}

class TrafficState {
  const TrafficState({
    required this.mode,
    required this.runningMode,
    required this.stage,
    required this.active,
    required this.counts,
    required this.sensorAge,
    required this.fallback,
    required this.receivedAt,
    this.reason,
  });

  factory TrafficState.fromJson(Map<String, dynamic> row) => TrafficState(
    mode: row['modo'] as String,
    runningMode: row['modo_activo'] as String,
    stage: row['etapa'] as String,
    active: Set<String>.from(row['activos'] as List),
    counts: List<int>.from(row['detectados'] as List),
    sensorAge: (row['edad_sensor'] as num).toDouble(),
    fallback: row['respaldo'] as bool,
    receivedAt: DateTime.parse(row['recibido_en'] as String),
    reason: row['motivo_texto'] as String?,
  );

  factory TrafficState.preview(DateTime now) {
    final cycle = now.second % 28;
    final stage = switch (cycle % 14) {
      < 10 => 'GREEN',
      < 13 => 'YELLOW',
      _ => 'ALL_RED',
    };
    return TrafficState(
      mode: 'adaptive',
      runningMode: 'adaptive',
      stage: stage,
      active: cycle < 14 ? {'N', 'S'} : {'E', 'W'},
      counts: cycle < 14 ? [5, 3, 4, 2] : [3, 6, 2, 4],
      sensorAge: 0.1,
      fallback: false,
      receivedAt: now,
    );
  }

  final String mode;
  final String runningMode;
  final String stage;
  final Set<String> active;
  final List<int> counts;
  final double sensorAge;
  final bool fallback;
  final DateTime receivedAt;
  final String? reason;

  bool isStale(DateTime now) =>
      now.difference(receivedAt) > const Duration(seconds: 3);

  Signal signal(Access access) {
    if (!active.contains(access.code)) return Signal.red;
    return switch (stage) {
      'GREEN' => Signal.green,
      'YELLOW' => Signal.yellow,
      'ALL_RED' => Signal.red,
      _ => Signal.unknown,
    };
  }
}

class PhaseEvent {
  const PhaseEvent(this.stage, this.active, this.at, this.reason);

  factory PhaseEvent.fromJson(Map<String, dynamic> row) => PhaseEvent(
    row['etapa'] as String,
    List<String>.from(row['activos'] as List),
    DateTime.parse(row['ocurrido_en'] as String),
    row['motivo'] as String?,
  );

  final String stage;
  final List<String> active;
  final DateTime at;
  final String? reason;
}

class TrafficInterval {
  const TrafficInterval(this.label, this.autos, this.pickups, this.buses);

  factory TrafficInterval.fromJson(Map<String, dynamic> row, String label) =>
      TrafficInterval(
        label,
        (row['auto'] as num).toInt(),
        (row['camioneta'] as num).toInt(),
        (row['bus'] as num).toInt(),
      );

  final String label;
  final int autos;
  final int pickups;
  final int buses;
  int get total => autos + pickups + buses;
}

class TrafficStats {
  const TrafficStats({
    required this.total,
    required this.hourly,
    required this.series,
    required this.profile,
    required this.byAccess,
    required this.byVehicle,
    required this.cuts,
  });

  factory TrafficStats.fromJson(
    Map<String, dynamic> row,
    DateTime start,
    DateTime end,
    DateTime now,
  ) {
    final hourly = row['unidad'] == 'hour';
    final reported = {
      for (final item in (row['serie'] as List).cast<Map<String, dynamic>>())
        item['periodo'] as String: item,
    };
    final steps = <TrafficInterval>[];
    final latestHour = DateFormat("yyyy-MM-dd'T'HH").format(chileTime(now));
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      for (var hour = 0; hour < (hourly ? 24 : 1); hour++) {
        final hourLabel = hour.toString().padLeft(2, '0');
        final key = '${isoDate(day)}T$hourLabel';
        if (hourly && key.compareTo(latestHour) > 0) break;
        final entry = reported['$key:00'];
        final label = hourly
            ? '$hourLabel h'
            : DateFormat('d MMM', 'es_CL').format(day);
        steps.add(
          entry == null
              ? TrafficInterval(label, 0, 0, 0)
              : TrafficInterval.fromJson(entry, label),
        );
      }
    }
    final reportedProfile = {
      for (final item
          in (row['perfil_horario'] as List).cast<Map<String, dynamic>>())
        item['hora'] as int: item,
    };
    return TrafficStats(
      total: (row['total'] as num).toInt(),
      hourly: hourly,
      series: steps,
      profile: List.generate(24, (hour) {
        final label = '${hour.toString().padLeft(2, '0')} h';
        final entry = reportedProfile[hour];
        return entry == null
            ? TrafficInterval(label, 0, 0, 0)
            : TrafficInterval.fromJson(entry, label);
      }),
      byAccess: Map<String, int>.from(row['por_acceso'] as Map),
      byVehicle: Map<String, int>.from(row['por_tipo'] as Map),
      cuts: Map<String, int>.from(row['cortes'] as Map),
    );
  }

  factory TrafficStats.preview(DateTime start, DateTime end, Access? access) {
    final days = end.difference(start).inDays + 1;
    final hourly = days <= 2;
    final profile = List.generate(24, (hour) {
      const volumes = [
        1,
        0,
        0,
        0,
        1,
        2,
        12,
        24,
        32,
        23,
        15,
        13,
        21,
        25,
        20,
        18,
        22,
        28,
        34,
        26,
        14,
        9,
        6,
        3,
      ];
      final volume = (volumes[hour] * days / (access == null ? 1 : 4)).round();
      return TrafficInterval(
        '${hour.toString().padLeft(2, '0')} h',
        volume * 3,
        volume,
        volume ~/ 3,
      );
    });
    final series = hourly
        ? profile
        : List.generate(days, (index) {
            final label = DateFormat(
              'd MMM',
              'es_CL',
            ).format(start.add(Duration(days: index)));
            final volume = (42 + (index * 17) % 49) ~/ (access == null ? 1 : 4);
            return TrafficInterval(label, volume * 3, volume, volume ~/ 3);
          });
    final autos = series.fold(0, (sum, item) => sum + item.autos);
    final pickups = series.fold(0, (sum, item) => sum + item.pickups);
    final buses = series.fold(0, (sum, item) => sum + item.buses);
    final total = autos + pickups + buses;
    return TrafficStats(
      total: total,
      hourly: hourly,
      series: series,
      profile: profile,
      byAccess: access == null
          ? {
              'N': total ~/ 3,
              'E': total ~/ 4,
              'S': total ~/ 5,
              'W': total - total ~/ 3 - total ~/ 4 - total ~/ 5,
            }
          : {access.code: total},
      byVehicle: {'auto': autos, 'camioneta': pickups, 'bus': buses},
      cuts: {
        'sin_demanda': 3 * days,
        'verde_maximo': 8 * days,
        'balance_colas': 2 * days,
      },
    );
  }

  final int total;
  final bool hourly;
  final List<TrafficInterval> series;
  final List<TrafficInterval> profile;
  final Map<String, int> byAccess;
  final Map<String, int> byVehicle;
  final Map<String, int> cuts;
}

class Incident {
  const Incident(
    this.id,
    this.type,
    this.description,
    this.state,
    this.createdAt,
    this.photoPath,
  );

  factory Incident.fromJson(Map<String, dynamic> row) => Incident(
    row['id'] as String,
    row['tipo'] as String,
    row['descripcion'] as String,
    row['estado'] as String,
    DateTime.parse(row['creada_en'] as String),
    row['foto_path'] as String?,
  );

  final String id;
  final String type;
  final String description;
  final String state;
  final DateTime createdAt;
  final String? photoPath;
}

class IncidentChange {
  const IncidentChange(this.state, this.note, this.at, {this.responsible});

  final String state;
  final String? note;
  final DateTime at;
  final String? responsible;
}

class AccountApiException implements Exception {
  const AccountApiException(this.message);

  final String message;
}

class IncidentPhoto {
  const IncidentPhoto._(this.bytes, this.extension, this.mime);

  factory IncidentPhoto.fromBytes(Uint8List bytes) {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('La foto supera los 5 MB.');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return IncidentPhoto._(bytes, 'jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG' &&
        bytes[0] == 137) {
      return IncidentPhoto._(bytes, 'png', 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return IncidentPhoto._(bytes, 'webp', 'image/webp');
    }
    throw const FormatException('Selecciona una foto JPEG, PNG o WebP.');
  }

  final Uint8List bytes;
  final String extension;
  final String mime;
}

class TrafficRepository {
  const TrafficRepository(this.client);

  final SupabaseClient client;

  Future<Role> role(String id) async {
    final row = await client
        .from('perfiles')
        .select('rol')
        .eq('id', id)
        .maybeSingle();
    return Role.fromCode(row?['rol'] as String?);
  }

  Future<String> crossingName() async {
    final row = await client
        .from('cruces')
        .select('nombre')
        .eq('id', cruceId)
        .maybeSingle();
    return row?['nombre'] as String? ?? previewName;
  }

  Future<TrafficState?> readState() async {
    final row = await client
        .from('estado_cruce')
        .select()
        .eq('cruce_id', cruceId)
        .maybeSingle();
    return row == null ? null : TrafficState.fromJson(row);
  }

  Future<List<PhaseEvent>> readEvents() async {
    final rows = await client
        .from('eventos_fase')
        .select()
        .eq('cruce_id', cruceId)
        .order('ocurrido_en')
        .limit(8);
    return rows.map(PhaseEvent.fromJson).toList();
  }

  Future<TrafficStats> stats(
    DateTime start,
    DateTime end,
    Access? access,
  ) async {
    final result = await client.rpc(
      'estadisticas_trafico',
      params: {
        'p_cruce': cruceId,
        'p_desde': isoDate(start),
        'p_hasta': isoDate(end),
        'p_acceso': access?.code,
      },
    );
    return TrafficStats.fromJson(
      result as Map<String, dynamic>,
      start,
      end,
      DateTime.now(),
    );
  }

  Future<List<Incident>> incidents(String? user) async {
    final query = client.from('incidencias').select().eq('cruce_id', cruceId);
    final rows = await (user == null ? query : query.eq('autor_id', user))
        .order('creada_en', ascending: false);
    return rows.map(Incident.fromJson).toList();
  }

  Future<Incident?> incident(String id) async {
    final row = await client
        .from('incidencias')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Incident.fromJson(row);
  }

  Future<List<IncidentChange>> history(String id) async {
    final rows = await client
        .from('incidencias_historial')
        .select('estado_nuevo,nota,cambiado_en,responsable_id')
        .eq('incidencia_id', id)
        .order('cambiado_en', ascending: true);
    final ids = rows
        .map((row) => row['responsable_id'])
        .whereType<String>()
        .toSet();
    final names = <String, String>{};
    if (ids.isNotEmpty) {
      final profiles = await client
          .from('perfiles')
          .select('id,nombre')
          .inFilter('id', ids.toList());
      for (final profile in profiles) {
        if (profile['nombre'] case final String name when name.isNotEmpty) {
          names[profile['id'] as String] = name;
        }
      }
    }
    return rows
        .map(
          (item) => IncidentChange(
            item['estado_nuevo'] as String,
            item['nota'] as String?,
            DateTime.parse(item['cambiado_en'] as String),
            responsible: names[item['responsable_id']],
          ),
        )
        .toList();
  }

  Future<String> photoUrl(String path) =>
      client.storage.from('incidencias').createSignedUrl(path, 300);

  Future<void> changeIncident(String id, String state, String? note) async {
    final closing = state == 'resuelta';
    final normalized = note?.trim() ?? '';
    if (incidentNoteError(normalized, closing: closing) case final error?) {
      throw FormatException(error);
    }
    if (closing) {
      final current = await incident(id);
      if (current == null || current.state == 'resuelta') {
        throw StateError('La incidencia ya no está disponible para cerrar.');
      }
      if (current.photoPath case final path?) {
        await client.storage.from('incidencias').remove([path]);
      }
    }
    await client.rpc(
      'cambiar_estado_incidencia',
      params: {
        'p_incidencia': id,
        'p_estado': state,
        'p_nota': normalized.isEmpty ? null : normalized,
      },
    );
  }

  Future<void> deleteAccount() async {
    final current = client.auth.currentSession;
    final session = current?.isExpired == true
        ? (await client.auth.refreshSession()).session
        : current;
    const invalidSession = AccountApiException(
      'Vuelve a iniciar sesión para eliminar tu cuenta.',
    );
    if (session == null) throw invalidSession;
    final endpoint = httpsEndpoint(accountUrl);
    final connection = HttpsOriginClient(endpoint);
    final http.Response response;
    try {
      response = await connection
          .delete(
            endpoint,
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 25));
    } finally {
      connection.close();
    }
    if (response.statusCode == 401) throw invalidSession;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && body['eliminada'] == true) {
      await client.auth.signOut(scope: SignOutScope.local);
      return;
    }
    throw AccountApiException(
      response.statusCode == 502 && body['error'] is String
          ? body['error'] as String
          : 'No se pudo confirmar la eliminación de la cuenta.',
    );
  }

  Future<void> report({
    required String user,
    required String type,
    required String description,
    IncidentPhoto? photo,
  }) async {
    final storage = client.storage.from('incidencias');
    String? path;
    if (photo != null) {
      final suffix = Random.secure().nextInt(0x100000000).toRadixString(16);
      path =
          '$user/${DateTime.now().microsecondsSinceEpoch}-$suffix.${photo.extension}';
      await storage.uploadBinary(
        path,
        photo.bytes,
        fileOptions: FileOptions(contentType: photo.mime),
      );
    }
    try {
      await client.from('incidencias').insert({
        'cruce_id': cruceId,
        'tipo': type,
        'descripcion': description,
        'foto_path': path,
      });
    } on PostgrestException catch (error) {
      final rejected = [
        '22',
        '23',
        '42',
        'P0001',
        'PGRST3',
      ].any((prefix) => error.code?.startsWith(prefix) ?? false);
      if (path != null && rejected) {
        await storage.remove([path]).then<void>((_) {}, onError: (Object _) {});
      }
      rethrow;
    }
  }
}
