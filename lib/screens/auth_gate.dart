import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/mock_travel_repository.dart';
import '../data/supabase_travel_repository.dart';
import '../data/travel_repository.dart';
import '../state/app_state.dart';
import 'auth_screen.dart';
import 'home_shell.dart';

/// Decides which repository the app runs on, based on the session.
///
/// The swap happens here and nowhere else: [AppState] is rebuilt with a new
/// repository whenever the session changes, so signing in or out reloads the
/// data without any screen knowing why.
class AuthGate extends StatefulWidget {
  final TileProvider? mapTileProvider;

  const AuthGate({super.key, this.mapTileProvider});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _sampleMode = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return _shell(
            key: ValueKey('user-${session.user.id}'),
            repository: SupabaseTravelRepository(),
            onSignOut: () => Supabase.instance.client.auth.signOut(),
          );
        }

        if (_sampleMode) {
          return _shell(
            key: const ValueKey('sample'),
            repository: MockTravelRepository(),
            onSignOut: () => setState(() => _sampleMode = false),
          );
        }

        return AuthScreen(
          onBrowseSample: () => setState(() => _sampleMode = true),
        );
      },
    );
  }

  Widget _shell({
    required Key key,
    required TravelRepository repository,
    required VoidCallback onSignOut,
  }) {
    // The key matters: it forces a fresh AppState (and therefore a fresh load)
    // when the identity behind the data changes.
    return ChangeNotifierProvider(
      key: key,
      create: (_) => AppState(repository),
      child: HomeShell(
        mapTileProvider: widget.mapTileProvider,
        onSignOut: onSignOut,
      ),
    );
  }
}
