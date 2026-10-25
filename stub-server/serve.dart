/// A stand-in for the Localaze read API, backed by the shared fixtures.
///
/// The example apps need a server that can be made to offer a patch, a major,
/// or a catalog with a retyped parameter, on demand. The real backend can do
/// all of that, but only by publishing releases, which is a slow way to check
/// that a refusal works.
///
/// This serves the **same endpoints, with the same headers**, so an app pointed
/// at it behaves exactly as it does against production, and a generator pointed
/// at it generates exactly what it would from a real release:
///
///   GET /api/v1/read/manifest[?version=1.0.0]
///   GET /api/v1/read/version
///   GET /api/v1/read/translations/{lang}?format=resolved[&version=x.y.z]
///
/// plus control endpoints the example apps call to change what is on offer.
/// Those are the only thing here the real server does not have, and they are
/// under /control/ so the difference is obvious.
///
/// Run:  dart run serve.dart [--port 8787]
///
/// No dependencies, so it needs no pub get.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String apiKey = 'demo-key';

/// What the server is currently offering.
///
/// Each scenario is one of the shared fixtures, so the apps demonstrate exactly
/// the cases the conformance suites assert on.
enum Scenario {
  /// 1.0.0. What the app was generated from — nothing to take.
  base('1.0.0', 'PATCH', 'the version the app was built against'),

  /// 1.0.1. Wording only. Accepted under every policy but `none`.
  patch('1.0.1', 'PATCH', 'a wording fix — sign out becomes Выйти'),

  /// 1.1.0. Adds a key. Accepted under minorAndPatch, refused under patchOnly.
  minor('1.1.0', 'MINOR', 'adds settings.title, which no accessor references'),

  /// 1.0.2. A patch that retypes count from NUMBER to STRING.
  ///
  /// The interesting one: policy accepts it, the key set is intact, and the
  /// parameter is still named "count". Only a type-aware signature check
  /// refuses it.
  retyped('1.0.2', 'PATCH', 'a patch that retypes count — refused by signature'),

  /// 2.0.0. Drops a key. Refused under every policy.
  major('2.0.0', 'MAJOR', 'drops auth.sign_out — refused whatever the policy'),

  /// A body with no messages, to exercise the malformed path.
  malformed('1.0.4', 'PATCH', 'a body with no messages'),

  /// Every request fails, to exercise the offline path.
  down('1.0.0', 'PATCH', 'the server is unreachable');

  const Scenario(this.version, this.bump, this.description);

  final String version;
  final String bump;
  final String description;
}

Scenario current = Scenario.base;

/// Fixture file per scenario, for Russian. Azerbaijani has no update fixtures,
/// so it always serves the base catalog — which is realistic: a release rarely
/// touches every language.
const Map<Scenario, String> ruFixture = {
  Scenario.base: 'catalogs/ru.json',
  Scenario.patch: 'updates/patch-1.0.1-ru.json',
  Scenario.minor: 'updates/minor-1.1.0-ru.json',
  Scenario.retyped: 'updates/retyped-1.0.2-ru.json',
  Scenario.major: 'updates/major-2.0.0-ru.json',
  Scenario.malformed: 'updates/malformed-shape-ru.json',
  Scenario.down: 'catalogs/ru.json',
};

late final Directory fixtures;

Future<void> main(List<String> args) async {
  final port = _intArg(args, '--port') ?? 8787;
  // Beside this script, wherever it is run from: the contract's own checkout,
  // or the contract/ submodule inside an SDK repository.
  fixtures = Directory.fromUri(Platform.script.resolve('../fixtures/'));

  if (!fixtures.existsSync()) {
    stderr.writeln('Fixtures not found at ${fixtures.path}.');
    stderr.writeln('Run this from a checkout of localaze-contract, which has fixtures/ beside stub-server/.');
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  _printBanner(port);

  await for (final request in server) {
    try {
      await _handle(request);
    } catch (error) {
      // A stub that crashes mid-demo is worse than one that 500s.
      stderr.writeln('unhandled: $error');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}

Future<void> _handle(HttpRequest request) async {
  final path = request.uri.path;

  // CORS, so the Flutter web build can call this from a browser. The real
  // server does not need it because apps are native; a demo does.
  request.response.headers
    ..add('Access-Control-Allow-Origin', '*')
    ..add('Access-Control-Allow-Headers', 'X-Localaze-Key, If-None-Match, Accept')
    ..add('Access-Control-Expose-Headers', 'ETag');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.ok;
    return request.response.close();
  }

  if (path.startsWith('/control')) return _control(request);

  if (current == Scenario.down) {
    _log(request, 503, 'scenario down');
    request.response.statusCode = HttpStatus.serviceUnavailable;
    return request.response.close();
  }

  // The real API authenticates with this header, and the key carries the
  // project and the environment. Getting it wrong must look like a 401 here
  // too, or the examples cannot demonstrate telling a bad key from a quiet
  // network.
  if (request.headers.value('X-Localaze-Key') != apiKey) {
    _log(request, 401, 'bad or missing X-Localaze-Key');
    request.response.statusCode = HttpStatus.unauthorized;
    return request.response.close();
  }

  if (path == '/api/v1/read/manifest') return _manifest(request);
  if (path == '/api/v1/read/version') return _version(request);
  if (path.startsWith('/api/v1/read/translations/')) return _translations(request);

  _log(request, 404, '');
  request.response.statusCode = HttpStatus.notFound;
  await request.response.close();
}

/// The manifest of the release the apps are built against.
///
/// Only `base` has one: the update scenarios exist to be offered to an app
/// that was already generated, not to generate from. Asking for another
/// version is a 404 naming the one that exists, as the real server does.
Future<void> _manifest(HttpRequest request) async {
  final pinned = request.uri.queryParameters['version'];
  if (pinned != null && pinned != Scenario.base.version) {
    _log(request, 404, 'no manifest for $pinned');
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'detail': 'Version $pinned has no manifest here. '
            'Available: ${Scenario.base.version}.',
      }));
    return request.response.close();
  }

  _log(request, 200, 'manifest ${Scenario.base.version}');
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(File('${fixtures.path}/manifest.json').readAsStringSync());
  await request.response.close();
}

Future<void> _version(HttpRequest request) async {
  final body = jsonEncode({
    'environment': 'demo',
    'version': current.version,
    'bump': current.bump,
    'note': current.description,
    'publishedAt': '2026-08-01T00:00:00Z',
    'keyCount': 4,
    'available': [for (final scenario in Scenario.values) scenario.version],
  });

  _log(request, 200, 'version ${current.version}');
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json;
  request.response.write(body);
  await request.response.close();
}

Future<void> _translations(HttpRequest request) async {
  final language = request.uri.pathSegments.last;
  final pinned = request.uri.queryParameters['version'];

  // A pin means the release cannot move underneath a build, so it selects the
  // scenario rather than whatever is currently on offer.
  final scenario = pinned == null
      ? current
      : Scenario.values.firstWhere((s) => s.version == pinned,
          orElse: () => current);

  final file = language == 'ru'
      ? ruFixture[scenario]!
      : 'catalogs/az.json'; // no az update fixtures; a release rarely touches every language

  final raw = File('${fixtures.path}/$file');
  if (!raw.existsSync()) {
    _log(request, 404, 'no fixture $file');
    request.response.statusCode = HttpStatus.notFound;
    return request.response.close();
  }

  final body = raw.readAsStringSync();

  // Version-scoped, exactly as the real server does it, so a pinned version's
  // tag never changes and a rollback returns the earlier tag rather than
  // inventing a new one.
  final etag = '"${scenario.version}-${language}"';

  if (request.headers.value('If-None-Match') == etag) {
    _log(request, 304, 'not modified');
    request.response
      ..statusCode = HttpStatus.notModified
      ..headers.add(HttpHeaders.etagHeader, etag);
    return request.response.close();
  }

  _log(request, 200, '$language ${scenario.version} from $file');
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..headers.add(HttpHeaders.etagHeader, etag);
  request.response.write(body);
  await request.response.close();
}

/// The control surface, which the real server does not have.
///
/// GET so it works from a browser, from curl, and from a button in an example
/// app without a body to construct.
Future<void> _control(HttpRequest request) async {
  final segments = request.uri.pathSegments;

  if (segments.length >= 2 && segments[1] == 'scenarios') {
    final body = jsonEncode({
      'current': current.name,
      'scenarios': [
        for (final scenario in Scenario.values)
          {
            'name': scenario.name,
            'version': scenario.version,
            'bump': scenario.bump,
            'description': scenario.description,
          }
      ],
    });
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json;
    request.response.write(body);
    return request.response.close();
  }

  if (segments.length >= 3 && segments[1] == 'serve') {
    final wanted = segments[2];
    final scenario = Scenario.values.where((s) => s.name == wanted).firstOrNull;

    if (scenario == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('unknown scenario "$wanted"; try one of '
            '${Scenario.values.map((s) => s.name).join(', ')}');
      return request.response.close();
    }

    current = scenario;
    stdout.writeln('\n  ▸ now serving ${scenario.name} '
        '(${scenario.version}) — ${scenario.description}\n');

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'current': scenario.name,
      'version': scenario.version,
      'description': scenario.description,
    }));
    return request.response.close();
  }

  request.response
    ..statusCode = HttpStatus.notFound
    ..write('try /control/scenarios or /control/serve/<name>');
  await request.response.close();
}

void _log(HttpRequest request, int status, String note) {
  final etag = request.headers.value('If-None-Match');
  stdout.writeln('  $status  ${request.method} ${request.uri}'
      '${etag == null ? '' : '  (If-None-Match: $etag)'}'
      '${note.isEmpty ? '' : '  — $note'}');
}

int? _intArg(List<String> args, String name) {
  final at = args.indexOf(name);
  if (at == -1 || at + 1 >= args.length) return null;
  return int.tryParse(args[at + 1]);
}

void _printBanner(int port) {
  stdout.writeln('''
Localaze stub read API on http://localhost:$port
  API key: $apiKey

  GET /api/v1/read/manifest[?version=1.0.0]
  GET /api/v1/read/version
  GET /api/v1/read/translations/{ru|az}?format=resolved[&version=x.y.z]

  GET /control/scenarios          what can be served
  GET /control/serve/<name>       switch what is on offer

Scenarios:''');

  for (final scenario in Scenario.values) {
    final marker = scenario == current ? '▸' : ' ';
    stdout.writeln('  $marker ${scenario.name.padRight(10)} '
        '${scenario.version.padRight(7)} ${scenario.description}');
  }
  stdout.writeln('');
}
