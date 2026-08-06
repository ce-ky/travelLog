/// Supabase connection settings.
///
/// The publishable key is a *client* key: it is meant to ship inside the app,
/// and it grants nothing on its own — every table it can reach is gated by the
/// row level security policies in `supabase/migrations/`. Those policies are
/// the actual security boundary, not this string.
///
/// The service_role key is the opposite: it bypasses RLS entirely. It must
/// never appear in this file, in the app, or in any client-side code.
///
/// Both values can be overridden at build time without editing this file:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ystuycqwumhhhapdsuss.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_Yybepofpr5GTQEiXFIXC7Q_RpadLkZC',
  );
}
