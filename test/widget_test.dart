import 'dart:typed_data';

import 'package:control_semaforos/design.dart';
import 'package:control_semaforos/main.dart';
import 'package:control_semaforos/traffic_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await initializeDateFormatting('es_CL');
  });

  test('interpreta los accesos N, E, S, W y vigencia desde recibido_en', () {
    final lastAt = DateTime.utc(2026, 11, 23, 20);
    final state = TrafficState.fromJson({
      'modo': 'adaptive',
      'modo_activo': 'adaptive',
      'etapa': 'YELLOW',
      'activos': ['E', 'W'],
      'detectados': [3, 9, 0, 2],
      'edad_sensor': 0.2,
      'respaldo': false,
      'reportado_en': '2026-11-23T19:30:00.000Z',
      'recibido_en': lastAt.toIso8601String(),
    });
    expect(state.signal(Access.north), Signal.red);
    expect(state.signal(Access.east), Signal.yellow);
    expect(state.signal(Access.west), Signal.yellow);
    expect(state.counts[Access.east.index], 9);
    expect(state.isStale(lastAt.add(const Duration(seconds: 3))), isFalse);
    expect(
      state.isStale(lastAt.add(const Duration(milliseconds: 3001))),
      isTrue,
    );
    expect(clock(lastAt), '17:00:00');
  });

  test('valida los formatos y tamaño del bucket privado', () {
    final jpeg = IncidentPhoto.fromBytes(
      Uint8List.fromList([255, 216, 255, 224]),
    );
    expect(jpeg.mime, 'image/jpeg');
    expect(jpeg.extension, 'jpg');
    expect(
      () => IncidentPhoto.fromBytes(Uint8List(5 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(
      () => IncidentPhoto.fromBytes(Uint8List.fromList([71, 73, 70])),
      throwsFormatException,
    );
  });

  test('la serie de hoy completa horas vacías en Santiago y omite futuras', () {
    final date = DateTime.utc(2026, 11, 23);
    final data = TrafficStats.fromJson(
      {
        'unidad': 'hour',
        'total': 5,
        'serie': [
          {'periodo': '2026-11-23T02:00', 'auto': 2, 'camioneta': 0, 'bus': 3},
        ],
        'perfil_horario': [
          {'hora': 2, 'auto': 2, 'camioneta': 0, 'bus': 3},
        ],
        'por_acceso': {'N': 5},
        'por_tipo': {'auto': 2, 'bus': 3},
        'cortes': {'sin_demanda': 1},
      },
      date,
      date,
      DateTime.utc(2026, 11, 23, 20),
    );
    expect(data.series.length, 18);
    expect(data.series[0].total, 0);
    expect(data.series[2].total, 5);
    expect(data.profile.length, 24);
    expect(data.cuts['sin_demanda'], 1);
  });

  testWidgets('demostración móvil abre monitoreo, estadísticas y detalle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CruceApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar demostración'));
    await tester.pumpAndSettle();
    expect(find.text('Plano del cruce'), findsOneWidget);
    expect(find.textContaining('Última lectura'), findsOneWidget);
    expect(find.text('Vehículos detectados'), findsOneWidget);
    expect(find.text('Demostración'), findsOneWidget);
    await tester.tap(find.text('Estadísticas'));
    await tester.pumpAndSettle();
    expect(find.text('Vehículos por día'), findsOneWidget);
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    expect(find.text('Vehículos por hora'), findsOneWidget);
    await tester.tap(find.text('Incidencias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intermitente'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del reporte'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monitoreo ancho muestra plano y accesos simultáneamente', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CruceApp(showDemo: true));
    await tester.pumpAndSettle();
    final picture = tester.getTopLeft(find.text('Plano del cruce'));
    final readings = tester.getTopLeft(
      find.byKey(const ValueKey('access-panel')),
    );
    expect(picture.dx, lessThan(readings.dx));
    expect((picture.dy - readings.dy).abs(), lessThan(20));
  });

  testWidgets('modo noche es global, opcional y se conserva al reabrir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final platform = tester.binding.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(platform.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    ThemeData themeAt(String label) =>
        Theme.of(tester.element(find.text(label).first));
    final appearance = find.byType(SwitchListTile);
    await tester.pumpWidget(CruceApp(showDemo: true, preferences: preferences));
    await tester.pumpAndSettle();
    expect(themeAt('Plano del cruce').scaffoldBackgroundColor, Colors.white);
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(appearance).value, isFalse);
    await tester.tap(find.text('Modo noche'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(appearance).value, isTrue);

    for (final (tab, heading) in [
      ('Monitoreo', 'Plano del cruce'),
      ('Estadísticas', 'Vehículos por día'),
      ('Incidencias', 'Intermitente'),
    ]) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(
        themeAt(heading).scaffoldBackgroundColor,
        CrucePalette.night.background,
      );
      expect(themeAt(heading).colorScheme.surface, CrucePalette.night.panel);
    }
    await tester.tap(find.text('Intermitente'));
    await tester.pumpAndSettle();
    expect(themeAt('Detalle del reporte').brightness, Brightness.dark);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await preferences.reload();
    await tester.pumpWidget(CruceApp(showDemo: true, preferences: preferences));
    await tester.pumpAndSettle();
    expect(themeAt('Plano del cruce').brightness, Brightness.dark);
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(appearance).value, isTrue);
    await tester.tap(find.text('Modo noche'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(appearance).value, isFalse);
    expect(themeAt('Modo noche').scaffoldBackgroundColor, Colors.white);
    await tester.tap(find.text('Salir de la demostración'));
    await tester.pumpAndSettle();
    expect(themeAt('Explorar demostración').brightness, Brightness.light);
  });
}
