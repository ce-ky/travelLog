import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Full-screen map where a tap drops the pin. Returns the chosen [LatLng],
/// or null if the user backs out.
class LocationPickerScreen extends StatefulWidget {
  final LatLng initialCenter;
  final LatLng? initialPoint;
  final TileProvider? tileProvider;

  const LocationPickerScreen({
    super.key,
    this.initialCenter = const LatLng(35.0, 135.76),
    this.initialPoint,
    this.tileProvider,
  });

  static Future<LatLng?> show(
    BuildContext context, {
    LatLng? initialPoint,
    LatLng? center,
  }) {
    return Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          initialCenter: center ?? initialPoint ?? const LatLng(35.0, 135.76),
          initialPoint: initialPoint,
        ),
      ),
    );
  }

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng? _picked = widget.initialPoint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择地点'),
        actions: [
          TextButton(
            onPressed: _picked == null
                ? null
                : () => Navigator.of(context).pop(_picked),
            child: const Text('完成'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 6,
              onTap: (_, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.travel_log',
                tileProvider: widget.tileProvider,
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              padding: const EdgeInsets.all(12),
              child: Text(
                _picked == null
                    ? '点击地图选择位置'
                    : '已选：${_picked!.latitude.toStringAsFixed(4)}, '
                        '${_picked!.longitude.toStringAsFixed(4)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
