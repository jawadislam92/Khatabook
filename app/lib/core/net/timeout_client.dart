import 'dart:async';

import 'package:http/http.dart' as http;

/// An HTTP client that gives up when the server stays silent.
///
/// supabase_flutter sets no timeout of its own, so a dropped connection
/// leaves a request pending for ever and the screen shows a spinner with no
/// way out. With this client the request fails with a [TimeoutException]
/// and the screen can show the error with a retry.
///
/// The limit applies twice: to the wait for the response to start, and to
/// any gap between two chunks of the response body.
///
/// A silent server fails with [RequestTimedOut]. The database client tries a
/// failed read three more times, which turned one 30 second wait into two
/// minutes of spinner; it does not repeat an aborted request, so the time
/// out is reported as one. The screens show the error with Try again and
/// keep trying in the background on their own.
class TimeoutClient extends http.BaseClient {
  TimeoutClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 30),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner
        .send(request)
        .timeout(timeout, onTimeout: () => throw RequestTimedOut(request.url));
    return http.StreamedResponse(
      response.stream.timeout(timeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// The server did not start answering within the time limit.
class RequestTimedOut extends http.RequestAbortedException {
  RequestTimedOut([super.uri]);

  @override
  String toString() => 'Request timed out: $uri';
}
