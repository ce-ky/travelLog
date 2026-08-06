import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/travel_repository.dart';
import 'screens/auth_gate.dart';
import 'screens/home_shell.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const TravelLogApp());
}

class TravelLogApp extends StatelessWidget {
  /// Test-only override: supplying a repository skips the auth gate entirely,
  /// so widget tests never touch Supabase.
  final TravelRepository? repository;

  /// Only widget tests set this, to keep the map off the network.
  final TileProvider? mapTileProvider;

  const TravelLogApp({super.key, this.repository, this.mapTileProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '旅行日志',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D8D7A),
        useMaterial3: true,
        // Classic ripple on every platform, so touch feedback feels the same
        // on phone, desktop and web (and it avoids the shader-backed sparkle).
        splashFactory: InkRipple.splashFactory,
      ),
      home: repository != null
          ? ChangeNotifierProvider(
              create: (_) => AppState(repository!),
              child: HomeShell(mapTileProvider: mapTileProvider),
            )
          : AuthGate(mapTileProvider: mapTileProvider),
    );
  }
}
