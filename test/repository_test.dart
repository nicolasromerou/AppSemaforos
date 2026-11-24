import 'dart:convert';

import 'package:control_semaforos/traffic_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'lee el cruce y llama a la RPC de estadísticas del repositorio',
    () async {
      final client = SupabaseClient(
        'https://cruce.test',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          expect(request.headers['apikey'], 'sb_publishable_test');
          if (request.url.path == '/rest/v1/estado_cruce') {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['cruce_id'], 'eq.maqueta-01');
            return _json(request, [
              {
                'modo': 'adaptive',
                'modo_activo': 'adaptive',
                'etapa': 'GREEN',
                'activos': ['N', 'S'],
                'detectados': [5, 3, 4, 2],
                'edad_sensor': 0.1,
                'respaldo': false,
                'recibido_en': '2026-11-23T20:15:03.250Z',
              },
            ]);
          }
          expect(request.url.path, '/rest/v1/rpc/estadisticas_trafico');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'p_cruce': 'maqueta-01',
            'p_desde': '2026-11-23',
            'p_hasta': '2026-11-23',
            'p_acceso': 'E',
          });
          return _json(request, {
            'unidad': 'hour',
            'total': 0,
            'serie': [],
            'perfil_horario': [],
            'por_acceso': {},
            'por_tipo': {},
            'cortes': {},
          });
        }),
      );
      addTearDown(client.dispose);
      final repository = TrafficRepository(client);
      final state = await repository.readState();
      expect(state?.counts, [5, 3, 4, 2]);
      expect(state?.signal(Access.north), Signal.green);
      final day = DateTime.utc(2026, 11, 23);
      expect((await repository.stats(day, day, Access.east)).total, 0);
    },
  );

  test('envía una incidencia con las cuatro columnas permitidas', () async {
    final client = SupabaseClient(
      'https://cruce.test',
      'sb_publishable_test',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/incidencias');
        expect(jsonDecode(request.body), {
          'cruce_id': 'maqueta-01',
          'tipo': 'luz_apagada',
          'descripcion': 'La luz del acceso norte no enciende.',
          'foto_path': null,
        });
        return http.Response('', 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    await TrafficRepository(client).report(
      user: '00000000-0000-4000-8000-00000000000a',
      type: 'luz_apagada',
      description: 'La luz del acceso norte no enciende.',
    );
  });

  for (final storageFails in [false, true]) {
    test(
      storageFails
          ? 'mantiene abierta la incidencia si falla el borrado'
          : 'borra la foto antes de cerrar la incidencia',
      () async {
        const id = '00000000-0000-4000-8000-00000000000b';
        const path = '00000000-0000-4000-8000-00000000000a/foto.jpg';
        final requests = <String>[];
        final client = SupabaseClient(
          'https://cruce.test',
          'sb_publishable_test',
          httpClient: MockClient((request) async {
            requests.add(request.method);
            switch (request.method) {
              case 'GET':
                expect(request.url.path, '/rest/v1/incidencias');
                return _json(request, [
                  {
                    'id': id,
                    'tipo': 'luz_apagada',
                    'descripcion': 'Luz apagada en norte',
                    'estado': 'en_revision',
                    'creada_en': '2026-11-23T20:15:03.250Z',
                    'foto_path': path,
                  },
                ]);
              case 'DELETE':
                expect(request.url.path, '/storage/v1/object/incidencias');
                expect(jsonDecode(request.body), {
                  'prefixes': [path],
                });
                return storageFails
                    ? _json(request, {
                        'message': 'Acceso rechazado',
                      }, status: 403)
                    : _json(request, []);
              default:
                expect(
                  request.url.path,
                  '/rest/v1/rpc/cambiar_estado_incidencia',
                );
                expect(jsonDecode(request.body), {
                  'p_incidencia': id,
                  'p_estado': 'resuelta',
                  'p_nota': 'Luz revisada',
                });
                return http.Response('', 204, request: request);
            }
          }),
        );
        addTearDown(client.dispose);
        final change = TrafficRepository(
          client,
        ).changeIncident(id, 'resuelta', 'Luz revisada');
        if (storageFails) {
          await expectLater(change, throwsA(isA<StorageException>()));
          expect(requests, ['GET', 'DELETE']);
        } else {
          await change;
          expect(requests, ['GET', 'DELETE', 'POST']);
        }
      },
    );
  }

  test('rechaza notas inválidas antes de tocar la foto del reporte', () async {
    const id = '00000000-0000-4000-8000-00000000000b';
    final requests = <String>[];
    final client = SupabaseClient(
      'https://cruce.test',
      'sb_publishable_test',
      httpClient: MockClient((request) async {
        requests.add(request.method);
        return switch (request.method) {
          'GET' => _json(request, [
            {
              'id': id,
              'tipo': 'luz_apagada',
              'descripcion': 'Luz apagada en norte',
              'estado': 'en_revision',
              'creada_en': '2026-11-23T20:15:03.250Z',
              'foto_path': '00000000-0000-4000-8000-00000000000a/foto.jpg',
            },
          ]),
          'DELETE' => _json(request, []),
          _ => _json(request, {
            'code': '23514',
            'message': 'La nota no cumple la restricción de longitud',
          }, status: 400),
        };
      }),
    );
    addTearDown(client.dispose);
    final repository = TrafficRepository(client);
    for (final note in [List.filled(501, '🇨🇱').join(), '   ']) {
      await expectLater(
        repository.changeIncident(id, 'resuelta', note),
        throwsFormatException,
      );
    }
    expect(requests, isEmpty);
  });
}

http.Response _json(
  http.Request request,
  Object response, {
  int status = 200,
}) => http.Response(
  jsonEncode(response),
  status,
  request: request,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
