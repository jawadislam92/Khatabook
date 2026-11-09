import 'dart:async';

import 'package:duebook/core/net/timeout_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

void main() {
  test('a server that never answers ends in RequestTimedOut', () async {
    final never = Completer<http.Response>();
    final client = TimeoutClient(
      inner: MockClient((_) => never.future),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      client.get(Uri.parse('https://example.test/')),
      throwsA(isA<RequestTimedOut>()),
    );
  });

  test('a normal answer passes through unchanged', () async {
    final client = TimeoutClient(
      inner: MockClient((_) async => http.Response('ok', 200)),
      timeout: const Duration(seconds: 5),
    );
    final response = await client.get(Uri.parse('https://example.test/'));
    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });

  test('the database client gives up after one silent try, not four', () async {
    var calls = 0;
    final never = Completer<http.Response>();
    final sb = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: TimeoutClient(
        inner: MockClient((_) {
          calls++;
          return never.future;
        }),
        timeout: const Duration(milliseconds: 50),
      ),
    );
    addTearDown(sb.dispose);
    await expectLater(
      sb.from('jobs').select().eq('id', 'x').maybeSingle(),
      throwsA(isA<RequestTimedOut>()),
    );
    expect(calls, 1);
  });
}
