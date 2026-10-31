import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';

/// Tamamlanan koridor geçişleri.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM HH:mm', 'tr_TR');
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final ps = tracker.passages;
        if (ps.isEmpty) {
          return const Center(child: Text('Henüz tamamlanmış geçiş yok.'));
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: ps.length,
                itemBuilder: (context, i) {
                  final p = ps[i];
                  final color = p.withinLimit ? Colors.greenAccent : Colors.redAccent;
                  return ListTile(
                    leading: Icon(p.withinLimit ? Icons.check_circle : Icons.warning, color: color),
                    title: Text('${p.corridorName} — ort. ${p.avgKmh.round()} km/s'),
                    subtitle: Text(
                        '${fmt.format(p.startedAt)} • ${(p.distanceM / 1000).toStringAsFixed(1)} km • '
                        '${p.endedAt.difference(p.startedAt).inMinutes} dk • '
                        'limit ${p.limitKmh} • en yüksek ${p.maxSpeedKmh.round()}'),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => tracker.clearPassages(),
              child: const Text('Geçmişi temizle'),
            ),
          ],
        );
      },
    );
  }
}
