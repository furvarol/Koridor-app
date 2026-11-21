import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models.dart';

/// Kayıtlı koridorların listesi; dokununca haritada gösterir, düzenler, siler.
class CorridorsScreen extends StatelessWidget {
  const CorridorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final cs = tracker.corridors;
        final importBtn = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () => _importOfficial(context),
            icon: const Icon(Icons.download),
            label: const Text('Ankara–İzmir resmi koridorlarını yükle'),
          ),
        );
        if (cs.isEmpty) {
          return Column(
            children: [
              importBtn,
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Henüz koridor yok.\n\nSürüş ekranında takibi başlat; koridor giriş tabelasında "Koridor başlangıcı", çıkış tabelasında "Bitiş" bas.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          itemCount: cs.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return importBtn;
            final c = cs[i - 1];
            return ListTile(
              leading: const Icon(Icons.alt_route),
              title: Text(c.name),
              subtitle: Text(
                  '${(c.lengthM / 1000).toStringAsFixed(1)} km • limit ${c.limitKmh} km/s • yön ${c.startBearing.round()}°'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') await _edit(context, c);
                  if (v == 'delete') await _delete(context, c);
                  if (v == 'reverse') {
                    final r = await tracker.addReverse(c);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ters yön eklendi: ${r.name}')));
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(value: 'reverse', child: Text('Ters yönünü ekle')),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CorridorMapScreen(c)),
              ),
            );
          },
        );
      },
    );
  }

  /// APK'ya gömülü İçişleri Bakanlığı verisini (koridor-verisi/) ekler.
  Future<void> _importOfficial(BuildContext context) async {
    String msg;
    try {
      final raw = await rootBundle.loadString('koridor-verisi/ankara-izmir.json');
      final list = (jsonDecode(raw) as List)
          .map((e) => Corridor.fromJson(e as Map<String, dynamic>))
          .toList();
      final n = await tracker.importCorridors(list);
      msg = n == 0
          ? 'Resmi koridorlar zaten yüklü (${list.length} koridor).'
          : '$n resmi koridor eklendi (iki yön).';
    } catch (e) {
      msg = 'Yüklenemedi: $e';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _edit(BuildContext context, Corridor c) async {
    final nameCtrl = TextEditingController(text: c.name);
    final limitCtrl = TextEditingController(text: '${c.limitKmh}');
    final lenCtrl = TextEditingController(text: (c.lengthM / 1000).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koridoru düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Ad')),
            TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Limit (km/s)')),
            TextField(
                controller: lenCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Uzunluk (km)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok == true) {
      c.name = nameCtrl.text.trim();
      c.limitKmh = int.tryParse(limitCtrl.text) ?? c.limitKmh;
      final km = double.tryParse(lenCtrl.text.replaceAll(',', '.'));
      if (km != null && km > 0) c.lengthM = km * 1000;
      await tracker.updateCorridor(c);
    }
  }

  Future<void> _delete(BuildContext context, Corridor c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${c.name}" silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await tracker.deleteCorridor(c);
  }
}

class CorridorMapScreen extends StatelessWidget {
  final Corridor c;
  const CorridorMapScreen(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final start = LatLng(c.startLat, c.startLng);
    final end = LatLng(c.endLat, c.endLng);
    final track = c.track.map((p) => LatLng(p[0], p[1])).toList();
    final center = LatLng((c.startLat + c.endLat) / 2, (c.startLng + c.endLng) / 2);
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 12),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.furkanvarol.koridor',
          ),
          if (track.length > 1)
            PolylineLayer(polylines: [
              Polyline(points: track, color: Colors.blueAccent, strokeWidth: 4),
            ]),
          MarkerLayer(markers: [
            Marker(point: start, child: const Icon(Icons.play_circle, color: Colors.green, size: 36)),
            Marker(point: end, child: const Icon(Icons.flag_circle, color: Colors.red, size: 36)),
          ]),
        ],
      ),
    );
  }
}
