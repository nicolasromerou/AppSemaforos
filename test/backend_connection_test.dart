import 'package:control_semaforos/backend_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rechaza configuración sin HTTPS o con credenciales embebidas', () {
    for (final value in [
      'http://cruce.test',
      'https://',
      'https://usuario@cruce.test',
      'https://cruce.test/?token=local',
      'https://cruce.test/#fragmento',
    ]) {
      expect(() => httpsEndpoint(value), throwsFormatException);
    }
    expect(httpsEndpoint('https://cruce.test/').origin, 'https://cruce.test');
  });

  test('mantiene la sesión en el origen y desactiva redirecciones', () async {
    final sent = <Uri>[];
    final transport = MockClient.streaming((request, body) async {
      sent.add(request.url);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer sesion-de-prueba');
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        307,
        headers: {'location': 'https://otro.test/recibir'},
        request: request,
      );
    });
    final client = HttpsOriginClient(
      Uri.parse('https://cruce.test'),
      transport: transport,
    );
    addTearDown(client.close);
    const headers = {'Authorization': 'Bearer sesion-de-prueba'};
    final source = Uri.parse('https://cruce.test/rest/v1/estado_cruce?limit=1');
    final response = await client.get(source, headers: headers);
    expect(response.statusCode, 307);

    for (final value in [
      'http://cruce.test/rest/v1/estado_cruce',
      'https://otro.test/recibir',
      'https://cruce.test:8443/recibir',
      'https://usuario@cruce.test/recibir',
    ]) {
      await expectLater(
        client.get(Uri.parse(value), headers: headers),
        throwsA(isA<http.ClientException>()),
      );
    }
    expect(sent, [source]);
  });
}
