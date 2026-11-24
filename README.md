# Cruce · AppSemaforos

**Versión inicial 0.1.0**

Cruce es la app Flutter para Android del proyecto Semáforo Inteligente de INACAP Osorno. Permite consultar el estado de los semáforos y los conteos del cruce de la maqueta 3D (`maqueta-01`), revisar estadísticas de tránsito y reportar incidencias.

## Cómo se conectan los tres repositorios

| Repositorio | Función |
| --- | --- |
| [GodotProyecto](https://github.com/nicolasromerou/GodotProyecto) | Ejecuta la maqueta 3D y publica lecturas del controlador, cambios de fase y conteos de vehículos. |
| [controlSemaforos](https://github.com/blec98/controlSemaforos) | Aloja la versión web, recibe datos de Godot en `POST /api/ingesta` y define las tablas, funciones y políticas de acceso en Supabase. |
| [AppSemaforos](https://github.com/nicolasromerou/AppSemaforos) | App Android. Inicia sesión con Supabase Auth y consulta las lecturas y operaciones disponibles para cada rol. |

Godot envía datos a la API de ingesta de la web. La API valida y guarda los datos en Supabase. Cruce recibe el estado del cruce mediante Realtime y vuelve a consultarlo cuando deja de actualizarse. Usa además el endpoint web `DELETE /api/cuenta` cuando la persona confirma la eliminación de su cuenta.

## Funciones de la app

- **Monitoreo.** Muestra el plano, las luces, el número de vehículos por acceso y la hora de la última lectura. Al superar tres segundos sin una lectura nueva, indica que los datos están desactualizados y conserva los últimos conteos registrados. La vista diurna va de 07:00 a 19:59, hora de Santiago.
- **Estadísticas.** Operadores y analistas pueden consultar rangos de fechas, filtrar por acceso y ver los conteos históricos de autos, camionetas y buses. La lectura en vivo contiene totales por acceso.
- **Incidencias.** Las personas pueden enviar reportes, adjuntar una foto y revisar el seguimiento. Los operadores pueden gestionar los reportes según sus permisos.

El [contrato para la app móvil](https://github.com/blec98/controlSemaforos/blob/main/docs/api-app.md) describe los datos, las operaciones y los permisos por rol.

## Ejecutar en Android

Se requiere Flutter 3.38 o compatible, Android SDK y un JDK compatible con Gradle 8.14. La compilación se verificó con JDK 21. Se admite Android 7.0 (API 24) o superior.

```sh
flutter doctor
flutter pub get
flutter run --dart-define=DEMO=true
```

La demostración identifica sus datos de ejemplo. Para usar el backend del equipo, copia `cruce.example.json` a `cruce.local.json`, completa la URL y la llave **publishable** de Supabase y usa una cuenta con correo confirmado. `cruce.local.json` se excluye de Git.

```sh
flutter run --dart-define-from-file=cruce.local.json
```

Para apuntar a otra instalación del backend, agrega `ACCOUNT_URL` con la URL HTTPS completa de su endpoint `/api/cuenta`. Esa instalación debe aplicar las [migraciones de controlSemaforos](https://github.com/blec98/controlSemaforos/tree/main/supabase/migrations).

## Verificar y compilar

```sh
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=cruce.local.json --obfuscate --split-debug-info=build/simbolos-android
```

Para distribuir el APK, configura la firma Android y conserva el almacén de claves y los símbolos en un lugar privado. La URL y la llave publicable pueden leerse del APK. Supabase valida la sesión y aplica permisos con políticas RLS. Las solicitudes HTTP se limitan al origen HTTPS configurado y rechazan redirecciones. El token de ingesta y las llaves privilegiadas se configuran únicamente en los servidores correspondientes.
