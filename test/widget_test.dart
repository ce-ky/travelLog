import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:travel_log/data/mock_travel_repository.dart';
import 'package:travel_log/main.dart';
import 'package:travel_log/screens/new_entry_sheet.dart';
import 'package:travel_log/state/app_state.dart';

/// A 1x1 transparent PNG, so the map renders without touching the network.
final _blankTile = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blankTile);
}

void main() {
  // These flows are written against the phone shell (bottom nav + FAB). The
  // default test window is 800px wide, which now crosses into the desktop
  // map-shell, so pin the window to a phone width for every test here.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.implicitView!;
    view.physicalSize = const Size(400, 800);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget app() => TravelLogApp(
        repository: MockTravelRepository(),
        mapTileProvider: _OfflineTileProvider(),
      );

  testWidgets('boots on the map view with the three nav destinations',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('旅途'), findsOneWidget);
    expect(find.text('浏览'), findsWidgets);
  });

  testWidgets('switches to the browse view and back', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();
    expect(find.text('旅途'), findsWidgets);

    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    // The browse tab offers both filter modes.
    expect(find.text('按类型'), findsOneWidget);
    expect(find.text('按同行人'), findsOneWidget);
  });

  testWidgets('creates a trip and it appears as a card', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();

    // Create a trip from the row at the top of the list.
    await tester.tap(find.text('新建旅途'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '旅途名称'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, '旅途名称'), '冰岛环岛');
    await tester.ensureVisible(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    // Sheet closed, and the new trip shows up as a card in the list, which
    // proves it went through the repository and back out via refresh().
    expect(find.text('旅途名称'), findsNothing);
    expect(find.text('冰岛环岛'), findsOneWidget);
  });

  testWidgets('tapping a trip card opens only that trip’s records',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('云南漫游'));
    await tester.pumpAndSettle();

    // The detail lists 云南漫游's records, not 京都之旅's.
    expect(find.text('在古城迷路的那晚'), findsOneWidget); // belongs to 云南漫游
    expect(find.text('鸭川边的午后'), findsNothing); // belongs to 京都之旅
  });

  testWidgets('a trip can be deleted from its card menu', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();
    expect(find.text('京都之旅'), findsOneWidget);

    // Open the card's menu and choose delete.
    final card = find.ancestor(
      of: find.text('京都之旅'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(
      of: card,
      matching: find.byIcon(Icons.more_vert),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // Confirm in the dialog.
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('京都之旅'), findsNothing);
  });

  testWidgets('an account with no trips is told where to start',
      (tester) async {
    await tester.pumpWidget(TravelLogApp(
      repository: MockTravelRepository(seed: false),
      mapTileProvider: _OfflineTileProvider(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();

    expect(find.text('还没有旅途'), findsOneWidget);
  });

  testWidgets('creates an entry and it lands in the type list', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Browse tab, then the FAB (icon-only) opens the entry form.
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('新增记录'), findsWidgets);

    // There is no title field anymore.
    expect(find.widgetWithText(TextFormField, '标题'), findsNothing);

    // Default type is 照片 (needs an image); the type chips live at the bottom
    // now, so scroll to them and switch to 随笔 (text only).
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '随笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '随笔'));
    await tester.pumpAndSettle();

    // With no title, the card derives its heading from the body.
    await tester.enterText(
        find.widgetWithText(TextFormField, '说些什么：'), '测试随笔正文');

    // Pick the trip via its chip (a compact ChoiceChip now, not a dropdown).
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '京都之旅'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '京都之旅'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // Sheet closed and the derived title shows in the list.
    expect(find.widgetWithText(TextFormField, '说些什么：'), findsNothing);
    expect(find.text('测试随笔正文'), findsOneWidget);
  });

  testWidgets('delete needs a confirm tap before removing a record',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    expect(find.text('鸭川边的午后'), findsOneWidget);

    // First tap on the card's delete icon arms the confirm state.
    final card = find.ancestor(
      of: find.text('鸭川边的午后'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(
      of: card,
      matching: find.byIcon(Icons.delete_outline),
    ));
    // A single frame — not pumpAndSettle, which would wait out the 3s
    // auto-revert timer the armed button starts.
    await tester.pump();

    // It now asks to confirm, and the record is still there.
    expect(find.text('是否确认？'), findsOneWidget);
    expect(find.text('鸭川边的午后'), findsOneWidget);

    // Second tap (which cancels the timer) actually deletes it. Bounded pumps
    // rather than pumpAndSettle, which would wait on the load spinner.
    await tester.tap(find.text('是否确认？'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('鸭川边的午后'), findsNothing);
  });

  testWidgets('new trip sheet offers companion selection', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅途'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建旅途'));
    await tester.pumpAndSettle();

    // The companions section and the seeded people are offered as chips.
    expect(find.text('同行人'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '小林'), findsOneWidget);
  });

  // Proves the map-tap → pre-filled-location half: given an initial point, the
  // entry sheet renders the place-name field (only shown when a point exists).
  testWidgets('entry sheet pre-fills a passed-in location', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => AppState(MockTravelRepository()),
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NewEntrySheet.show(
                context,
                initialPoint: const LatLng(35.4666, 139.6360),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '地点名称'), findsOneWidget);
  });

  testWidgets('a location near an existing trip auto-selects that trip',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => AppState(MockTravelRepository()),
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              // Near 京都之旅's records (~35.0, 135.77); 云南漫游 is ~1000km away.
              onPressed: () => NewEntrySheet.show(
                context,
                initialPoint: const LatLng(35.00, 135.77),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final kyoto =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '京都之旅'));
    final yunnan =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '云南漫游'));
    expect(kyoto.selected, isTrue); // within 50km → auto-selected
    expect(yunnan.selected, isFalse);
  });

  testWidgets('browsing by companion shows places visited together',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按同行人'));
    await tester.pumpAndSettle();

    // 妈妈 was on 云南漫游 only → its records appear, 京都之旅's don't.
    await tester.tap(find.widgetWithText(ChoiceChip, '妈妈'));
    await tester.pumpAndSettle();

    expect(find.text('在古城迷路的那晚'), findsOneWidget); // 云南漫游 record
    expect(find.text('鸭川边的午后'), findsNothing); // 京都之旅 record
  });
}
