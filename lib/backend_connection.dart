import 'package:http/http.dart' as http;

Uri httpsEndpoint(String value) {
  final endpoint = Uri.tryParse(value.trim());
  if (endpoint == null ||
      endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    throw const FormatException('La dirección del servicio debe usar HTTPS.');
  }
  return endpoint;
}

class HttpsOriginClient extends http.BaseClient {
  HttpsOriginClient(Uri endpoint, {http.Client? transport})
    : _origin = httpsEndpoint(endpoint.toString()).origin,
      _transport = transport ?? http.Client();

  final String _origin;
  final http.Client _transport;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.origin != _origin) {
      throw http.ClientException('Destino de conexión no autorizado.');
    }
    request.followRedirects = false;
    return _transport.send(request);
  }

  @override
  void close() => _transport.close();
}
