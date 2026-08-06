import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'entry_form.dart';

/// Presents [EntryForm] as a bottom sheet — used by the FAB, where there's no
/// map location to anchor to. (The map's tap-to-add uses a location popup
/// instead, hosting the same [EntryForm].)
class NewEntrySheet {
  const NewEntrySheet._();

  /// Returns true when an entry was created.
  static Future<bool> show(
    BuildContext context, {
    String? initialTripId,
    LatLng? initialPoint,
  }) async {
    // The sheet is a Navigator route — a sibling of the provider, not a
    // descendant — so hand AppState across the boundary explicitly.
    final appState = context.read<AppState>();

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ChangeNotifierProvider.value(
        value: appState,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: EntryForm(
                initialTripId: initialTripId,
                initialPoint: initialPoint,
                onSaved: () => Navigator.of(sheetContext).pop(true),
                onClose: () => Navigator.of(sheetContext).pop(false),
              ),
            ),
          ),
        ),
      ),
    );
    return created ?? false;
  }
}
