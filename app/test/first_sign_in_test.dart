// Right after the very first sign in, the books list must show the person's
// books. It used to keep the empty list read a moment before sign in.
import 'package:duebook/features/auth/auth_repository.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Like the real one: nobody signed in, no books.
class _BooksForSignedIn implements SpacesRepository {
  _BooksForSignedIn(this.auth);
  final AuthRepository auth;
  final _inner = PreviewSpacesRepository();

  @override
  Future<List<Space>> listMine() async =>
      auth.currentUser == null ? const [] : _inner.listMine();

  @override
  Future<Space> createGroup(String name, {bool business = false}) =>
      _inner.createGroup(name, business: business);
}

void main() {
  test('books load again once the person signs in', () async {
    final auth = PreviewAuthRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        spacesRepositoryProvider.overrideWithValue(_BooksForSignedIn(auth)),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container.listen(mySpacesProvider, (_, _) {});
    container.listen(currentUserProvider, (_, _) {});

    expect(await container.read(mySpacesProvider.future), isEmpty);
    await auth.signIn(email: 'nani@example.com', password: '123456');
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(mySpacesProvider.future), isNotEmpty);

    await auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(mySpacesProvider.future), isEmpty);
  });
}
