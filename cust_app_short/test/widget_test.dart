import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:jago_customer/widgets/jago_map_markers.dart';

void main() {
  testWidgets('JagoMapView fills Stack and builds FlutterMap', (tester) async {
    const center = LatLng(16.5062, 80.6480);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: JagoMapView(
                  initialCameraPosition: const CameraPosition(target: center, zoom: 14),
                  markers: {
                    const Marker(markerId: MarkerId('p'), position: center),
                    const Marker(markerId: MarkerId('d'), position: LatLng(16.52, 80.65)),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(fmap.FlutterMap), findsOneWidget);
    final size = tester.getSize(find.byType(fmap.FlutterMap));
    expect(size.width, greaterThan(100));
    expect(size.height, greaterThan(100));
  });
}
