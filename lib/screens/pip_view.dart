import 'package:flutter/material.dart';

import '../main.dart';
import '../tracker.dart';

/// PiP penceresinde gösterilen sade görünüm: yalnızca hız.
/// Koridordaysa ortalama hız (limite göre renkli), değilse anlık hız.
class PipView extends StatelessWidget {
  const PipView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final t = tracker;
        final c = t.active;
        String label;
        String value;
        String? sub;
        Color color = Colors.white;

        switch (t.mode) {
          case TrackerMode.inCorridor when c != null:
            final over = t.avgKmh > c.limitKmh;
            final near = !over && t.avgKmh > c.limitKmh - 3;
            color = over
                ? Colors.redAccent
                : near
                    ? Colors.orangeAccent
                    : Colors.greenAccent;
            label = 'ORT • ${c.limitKmh}';
            value = '${t.avgKmh.round()}';
            sub = 'anlık ${t.currentKmh.round()}';
          case TrackerMode.recording:
            label = 'KAYIT';
            value = '${t.currentKmh.round()}';
            sub = '${(t.recordingLengthM / 1000).toStringAsFixed(1)} km';
          default:
            label = 'km/s';
            value = '${t.currentKmh.round()}';
        }

        return Container(
          color: Colors.black,
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: t.mode == TrackerMode.inCorridor ? color : Colors.transparent, width: 3),
            ),
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 64, height: 1.05, fontWeight: FontWeight.w700, color: color)),
                  if (sub != null)
                    Text(sub, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
