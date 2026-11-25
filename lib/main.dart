import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'backend_connection.dart';
import 'design.dart';
import 'incidents.dart';
import 'monitor.dart';
import 'statistics.dart';
import 'traffic_data.dart';

const _nightModeKey = 'cruce.night_mode';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await initializeDateFormatting('es_CL');
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } catch (_) {}
  if (demoMode) {
    runApp(CruceApp(showDemo: true, preferences: preferences));
    return;
  }
  try {
    final config =
        jsonDecode(await rootBundle.loadString('assets/config/supabase.json'))
            as Map<String, dynamic>;
    final endpoint = httpsEndpoint(
      supabaseUrl.isEmpty ? config['url'] as String : supabaseUrl,
    );
    final key = supabaseKey.isEmpty
        ? config['publishableKey'] as String
        : supabaseKey;
    if (!key.startsWith('sb_publishable_')) {
      throw const FormatException('Falta la llave publicable del servicio.');
    }
    final connection = HttpsOriginClient(endpoint);
    try {
      await Supabase.initialize(
        url: endpoint.toString().replaceFirst(RegExp(r'/+$'), ''),
        publishableKey: key,
        httpClient: connection,
        debug: false,
      );
    } catch (_) {
      connection.close();
      rethrow;
    }
    runApp(
      CruceApp(client: Supabase.instance.client, preferences: preferences),
    );
  } catch (_) {
    runApp(CruceApp(startupError: true, preferences: preferences));
  }
}

class CruceApp extends StatefulWidget {
  const CruceApp({
    super.key,
    this.client,
    this.showDemo = false,
    this.startupError = false,
    this.preferences,
  });

  final SupabaseClient? client;
  final bool showDemo;
  final bool startupError;
  final SharedPreferences? preferences;

  @override
  State<CruceApp> createState() => _CruceAppState();
}

class _CruceAppState extends State<CruceApp> {
  late bool _nightMode = widget.preferences?.get(_nightModeKey) == true;
  final _lightTheme = appTheme(CrucePalette.light);
  final _nightTheme = appTheme(CrucePalette.night);

  Future<bool> setNightMode(bool enabled) async {
    setState(() => _nightMode = enabled);
    try {
      return await widget.preferences?.setBool(_nightModeKey, enabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cruce',
    debugShowCheckedModeBanner: false,
    locale: const Locale('es', 'CL'),
    supportedLocales: const [Locale('es', 'CL')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _lightTheme,
    darkTheme: _nightTheme,
    themeMode: _nightMode ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).appBarTheme.systemOverlayStyle!,
      child: child!,
    ),
    home: widget.startupError
        ? const Scaffold(
            body: SafeArea(
              child: PageBody(
                children: [
                  Brand(),
                  SizedBox(height: 18),
                  SectionTitle('No se pudo conectar al servicio'),
                  SizedBox(height: 9),
                  Text('Revisa la configuración de conexión de Cruce.'),
                ],
              ),
            ),
          )
        : _SessionGate(client: widget.client, showDemo: widget.showDemo),
  );
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.client, required this.showDemo});

  final SupabaseClient? client;
  final bool showDemo;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late bool _showDemo = widget.showDemo;
  User? _user;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    final auth = widget.client?.auth;
    _user = auth?.currentUser;
    _subscription = auth?.onAuthStateChange.listen((event) {
      final user = event.session?.user;
      if (mounted && (user?.id != _user?.id || user?.email != _user?.email)) {
        if (user == null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        setState(() => _user = user);
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showDemo) {
      return _Workspace(
        role: Role.analyst,
        onExitDemo: () => setState(() => _showDemo = false),
      );
    }
    if (_user case final user?) {
      return _ProfileGate(
        key: ValueKey(user.id),
        user: user,
        repository: TrafficRepository(widget.client!),
      );
    }
    return _Welcome(
      client: widget.client,
      onDemo: () => setState(() => _showDemo = true),
    );
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({super.key, required this.user, required this.repository});

  final User user;
  final TrafficRepository repository;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Future<Role> _role = _loadRole();

  Future<Role> _loadRole() => widget.repository
      .role(widget.user.id)
      .timeout(const Duration(seconds: 12));

  @override
  Widget build(BuildContext context) => FutureBuilder<Role>(
    future: _role,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return _Workspace(
          role: snapshot.data!,
          user: widget.user,
          repository: widget.repository,
        );
      }
      return Scaffold(
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo cargar tu perfil.'),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => setState(() => _role = _loadRole()),
                      child: const Text('Reintentar'),
                    ),
                    TextButton(
                      onPressed: () =>
                          _signOut(context, widget.repository.client),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class _Welcome extends StatefulWidget {
  const _Welcome({required this.client, required this.onDemo});

  final SupabaseClient? client;
  final VoidCallback onDemo;

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _private = true;
  bool _register = false;
  bool _busy = false;
  String? _error;
  String? _message;

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = widget.client!.auth;
      if (_register) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (mounted && response.session == null) {
          setState(() {
            _register = false;
            _password.clear();
            _message =
                'Confirma el correo desde el enlace que te enviamos y vuelve para ingresar.';
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'invalid_credentials' => 'El correo o la contraseña no coinciden.',
            'email_not_confirmed' => 'Confirma tu correo antes de ingresar.',
            'weak_password' => 'Elige una contraseña más segura.',
            'over_email_send_rate_limit' || 'over_request_rate_limit' =>
              'Espera un momento antes de volver a intentar.',
            _ => 'No se pudo completar la solicitud. Intenta de nuevo.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No hay conexión con el servicio de acceso.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.client != null;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Align(alignment: Alignment.centerLeft, child: Brand()),
        const SizedBox(height: 27),
        PageHeader(
          title: connected
              ? (_register ? 'Crea tu cuenta' : 'Inicia sesión')
              : 'Control de tránsito',
          subtitle: connected
              ? 'Cruce de la maqueta 3D'
              : 'Consulta el estado del cruce y sigue tus reportes.',
        ),
        const SizedBox(height: 22),
        if (connected) ...[
          AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Ingresa un correo válido.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _private,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onFieldSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        tooltip: _private
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () => setState(() => _private = !_private),
                        icon: Icon(
                          _private
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').isEmpty ? 'Ingresa tu contraseña.' : null,
                  ),
                  if (_message case final message?) ...[
                    const SizedBox(height: 12),
                    Notice(message),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Notice(error, alert: true),
                  ],
                  if (_register) ...[
                    const SizedBox(height: 12),
                    const Notice(
                      'Usamos tu correo para confirmar la cuenta. La descripción y la foto opcional se vinculan a tu cuenta para gestionar y seguir el reporte. La foto se elimina al resolver la incidencia.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'Conectando…'
                          : _register
                          ? 'Crear cuenta'
                          : 'Ingresar',
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _register = !_register;
                            _error = null;
                            _message = null;
                          }),
                    child: Text(
                      _register ? 'Ya tengo cuenta' : 'Crear cuenta ciudadana',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: widget.onDemo,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Explorar demostración'),
          ),
          const SizedBox(height: 11),
          Text(
            'Datos de ejemplo',
            style: type(
              12,
              FontWeight.w700,
              color: CrucePalette.of(context).secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 870;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1040 : 430),
                  child: wide
                      ? Row(
                          children: [
                            Expanded(flex: 4, child: form),
                            const SizedBox(width: 56),
                            Expanded(flex: 6, child: const CrossingPreview()),
                          ],
                        )
                      : form,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _Destination {
  monitor('Monitoreo', Icons.grid_view_rounded),
  statistics('Estadísticas', Icons.bar_chart_rounded),
  incidents('Incidencias', Icons.assignment_outlined),
  account('Cuenta', Icons.person_outline_rounded);

  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    required this.role,
    this.repository,
    this.user,
    this.onExitDemo,
  });

  final Role role;
  final TrafficRepository? repository;
  final User? user;
  final VoidCallback? onExitDemo;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  _Destination _selected = _Destination.monitor;
  final _visited = {_Destination.monitor};

  void _select(_Destination destination) => setState(() {
    _selected = destination;
    _visited.add(destination);
  });

  Widget _page(_Destination destination) => switch (destination) {
    _Destination.monitor => MonitorPage(
      repository: widget.repository,
      role: widget.role,
    ),
    _Destination.statistics => StatisticsPage(repository: widget.repository),
    _Destination.incidents => IncidentsPage(
      repository: widget.repository,
      userId: widget.user?.id,
      role: widget.role,
    ),
    _Destination.account => _Account(
      role: widget.role,
      user: widget.user,
      repository: widget.repository,
      onExitDemo: widget.onExitDemo,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final palette = CrucePalette.of(context);
    final destinations = _Destination.values
        .where(
          (destination) =>
              destination != _Destination.statistics || widget.role.isStaff,
        )
        .toList();
    final demo = widget.repository == null;
    final desktop = MediaQuery.sizeOf(context).width >= 850;
    final content = IndexedStack(
      index: destinations.indexOf(_selected),
      children: [
        for (final destination in destinations)
          KeyedSubtree(
            key: ValueKey(destination),
            child: _visited.contains(destination)
                ? _page(destination)
                : const SizedBox.shrink(),
          ),
      ],
    );
    if (desktop) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Container(
                width: 191,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: palette.panel,
                  border: Border(right: BorderSide(color: palette.border)),
                ),
                padding: const EdgeInsets.fromLTRB(13, 19, 13, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 7),
                      child: Brand(),
                    ),
                    const SizedBox(height: 30),
                    for (final destination in destinations) ...[
                      Semantics(
                        selected: _selected == destination,
                        child: Material(
                          color: _selected == destination
                              ? palette.selection
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          child: ListTile(
                            dense: true,
                            minLeadingWidth: 18,
                            horizontalTitleGap: 9,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                            leading: Icon(
                              destination.icon,
                              color: _selected == destination
                                  ? palette.accent
                                  : palette.secondary,
                              size: 20,
                            ),
                            title: Text(
                              destination.label,
                              style: type(
                                13,
                                FontWeight.w800,
                                color: _selected == destination
                                    ? palette.accent
                                    : palette.foreground,
                              ),
                            ),
                            onTap: () => _select(destination),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const Spacer(),
                    if (demo)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill('Demostración'),
                      ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          if (demo)
            const Padding(
              padding: EdgeInsets.only(right: 19),
              child: Center(child: StatusPill('Demostración')),
            ),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: content),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: destinations.indexOf(_selected),
          onDestinationSelected: (index) => _select(destinations[index]),
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _signOut(BuildContext context, SupabaseClient client) async {
  try {
    await client.auth.signOut(scope: SignOutScope.local);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar la sesión.')),
      );
    }
  }
}

class _Account extends StatefulWidget {
  const _Account({
    required this.role,
    required this.user,
    required this.repository,
    required this.onExitDemo,
  });

  final Role role;
  final User? user;
  final TrafficRepository? repository;
  final VoidCallback? onExitDemo;

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Se eliminarán tu cuenta, tus reportes, su historial y las fotos adjuntas. Esta acción es permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar cuenta'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await widget.repository!.deleteAccount();
    } catch (error) {
      if (mounted) {
        final message = error is AccountApiException
            ? error.message
            : 'No se pudo confirmar la eliminación de la cuenta.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      const PageHeader(title: 'Cuenta', subtitle: null),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_circle_outlined,
              color: CrucePalette.of(context).accent,
              size: 31,
            ),
            const SizedBox(height: 9),
            SectionTitle(widget.user?.email ?? 'Sesión de demostración'),
            const SizedBox(height: 5),
            Text(
              widget.role.label,
              style: type(
                13,
                FontWeight.w700,
                color: CrucePalette.of(context).secondary,
              ),
            ),
            const SizedBox(height: 17),
            OutlinedButton.icon(
              onPressed: _deleting
                  ? null
                  : widget.repository == null
                  ? widget.onExitDemo
                  : () => _signOut(context, widget.repository!.client),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                widget.repository == null
                    ? 'Salir de la demostración'
                    : 'Cerrar sesión',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: SwitchListTile(
          secondary: Icon(
            Icons.nightlight_outlined,
            color: CrucePalette.of(context).accent,
          ),
          title: const Text('Modo noche'),
          value: CrucePalette.of(context).isNight,
          onChanged: (enabled) async {
            final app = context.findAncestorStateOfType<_CruceAppState>()!;
            final saved = await app.setNightMode(enabled);
            if (!saved && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No se pudo guardar la apariencia.'),
                ),
              );
            }
          },
        ),
      ),
      if (widget.repository != null) ...[
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _deleting ? null : _delete,
            child: Text(
              _deleting ? 'Eliminando cuenta…' : 'Eliminar mi cuenta',
            ),
          ),
        ),
      ],
    ],
  );
}
