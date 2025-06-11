import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

void main() async {
  final db = PostgreSQLConnection(
    Platform.environment['DB_HOST'] ?? 'dpg-d107so63jp1c739n6pg0-a',
    5432,
    Platform.environment['DB_NAME'] ?? 'MipripityApp',
    username: Platform.environment['DB_USER'] ?? 'mipripityapp_user',
    password: Platform.environment['DB_PASSWORD'] ?? 'FuotafUoe0sWr4IYjuSkXeZ281mMOA53',
  );

  await db.open();

  final router = Router();

  // Add this root route
  router.get('/', (Request req) async {
    return Response.ok('Mipripity API is running');
  });

  router.get('/ping', (Request req) async {
    return Response.ok('API is live');
  });

  router.get('/users', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM users');
    return Response.ok(results.toString());
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
}
