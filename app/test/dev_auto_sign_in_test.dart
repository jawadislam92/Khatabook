// The local test login only ever works in the web build on this computer.
import 'package:duebook/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool allowed({
    bool web = true,
    String host = 'localhost',
    String e = 'qa@x',
    String p = 'pw',
  }) => devAutoSignInAllowed(isWeb: web, host: host, email: e, password: p);

  test('on for the web build on localhost with both values', () {
    expect(allowed(), isTrue);
    expect(allowed(host: '127.0.0.1'), isTrue);
  });

  test('off everywhere else', () {
    expect(
      allowed(web: false),
      isFalse,
      reason: 'phones never log in by themselves',
    );
    expect(allowed(host: 'duebook.sparkingasia.com'), isFalse);
    expect(allowed(host: 'localhost.evil.com'), isFalse);
    expect(allowed(e: ''), isFalse);
    expect(allowed(p: ''), isFalse);
  });

  test('normal builds have it off', () {
    expect(AppConfig.devAutoSignIn, isFalse);
  });
}
