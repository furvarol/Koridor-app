import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../tracker.dart';

/// Ana sürüş ekranı: büyük rakamlar, uyarı rengi, başlat/durdur ve koridor kaydı.
class DriveScreen extends StatelessWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final t = tracker;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _StatusBar(t),
              const SizedBox(height: 12),
              Expanded(
                child: switch (t.mode) {
                  TrackerMode.inCorridor => _CorridorView(t),
                  TrackerMode.recording => _RecordingView(t),
                  TrackerMode.idle => _IdleView(t),
                },
              ),
              const SizedBox(height: 12),
              _Controls(t),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  final Tracker t;
  const _StatusBar(this.t);
  @override
  Widget build(BuildContext context) {
    final acc = t.lastPos?.accuracy;
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: t.running ? Colors.greenAccent : Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(t.status, maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (acc != null)
          Text('GPS ±${acc.round()} m',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _IdleView extends StatelessWidget {
  final Tracker t;
  const _IdleView(this.t);
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${t.currentKmh.round()}', style: style.displayLarge?.copyWith(fontSize: 96, fontWeight: FontWeight.w300)),
        Text('km/s', style: style.titleMedium),
        const SizedBox(height: 24),
        Text(
          t.running
              ? 'Kayıtlı ${t.corridors.length} koridor izleniyor. Bir koridora girince otomatik başlar.'
              : 'Takibi başlat; koridora girince ortalama hız otomatik hesaplanır.',
          textAlign: TextAlign.center,
          style: style.bodyMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _CorridorView extends StatelessWidget {
  final Tracker t;
  const _CorridorView(this.t);

  @override
  Widget build(BuildContext context) {
    final c = t.active!;
    final style = Theme.of(context).textTheme;
    final over = t.avgKmh > c.limitKmh;
    final near = !over && t.avgKmh > c.limitKmh - 3;
    final color = over
        ? Colors.redAccent
        : near
            ? Colors.orangeAccent
            : Colors.greenAccent;
    final allowed = t.allowedKmh;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 3),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(c.name, style: style.titleLarge),
          Text('Limit ${c.limitKmh} km/s', style: style.bodyMedium),
          const Spacer(),
          Text('ORTALAMA', style: style.labelMedium),
          Text('${t.avgKmh.round()}',
              style: style.displayLarge?.copyWith(fontSize: 120, color: color, fontWeight: FontWeight.w600)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat('Anlık', '${t.currentKmh.round()}'),
              _Stat('En fazla', allowed >= 999 ? '—' : '${allowed.round()}'),
              _Stat('Kalan', '${(t.remainingM / 1000).toStringAsFixed(1)} km'),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: t.progress, minHeight: 8, color: color),
          const SizedBox(height: 8),
          Text(
            '${_fmt(t.elapsed)}  •  ${(t.distanceM / 1000).toStringAsFixed(1)} / ${(c.lengthM / 1000).toStringAsFixed(1)} km',
            style: style.bodySmall,
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(children: [
      Text(label, style: style.labelMedium),
      Text(value, style: style.headlineMedium),
    ]);
  }
}

class _RecordingView extends StatelessWidget {
  final Tracker t;
  const _RecordingView(this.t);
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 48),
        const SizedBox(height: 12),
        Text('Koridor kaydediliyor', style: style.titleLarge),
        const SizedBox(height: 8),
        Text('${(t.recordingLengthM / 1000).toStringAsFixed(2)} km', style: style.displayMedium),
        const SizedBox(height: 12),
        Text('Koridor bitiş tabelasını geçince "Bitiş" bas.',
            textAlign: TextAlign.center, style: style.bodyMedium?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final Tracker t;
  const _Controls(this.t);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () async {
              if (t.running) {
                await t.stop();
                WakelockPlus.disable();
              } else {
                final err = await t.start();
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  WakelockPlus.enable();
                }
              }
            },
            icon: Icon(t.running ? Icons.stop : Icons.play_arrow),
            label: Text(t.running ? 'Durdur' : 'Takibi başlat'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: switch (t.mode) {
            TrackerMode.recording => OutlinedButton.icon(
                onPressed: () => _finishRecording(context),
                icon: const Icon(Icons.flag),
                label: const Text('Bitiş'),
              ),
            _ => OutlinedButton.icon(
                onPressed: t.running && t.mode == TrackerMode.idle
                    ? () {
                        final err = t.beginRecording();
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        }
                      }
                    : null,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Koridor başlangıcı'),
              ),
          },
        ),
      ],
    );
  }

  Future<void> _finishRecording(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '110');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koridoru kaydet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Ad (örn. Siirt–Kurtalan)'),
            ),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hız limiti (km/s)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              tracker.cancelRecording();
              Navigator.pop(ctx, false);
            },
            child: const Text('Kaydı iptal et'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok == true) {
      final limit = int.tryParse(limitCtrl.text) ?? 110;
      final name = nameCtrl.text.trim().isEmpty ? 'Koridor ${tracker.corridors.length + 1}' : nameCtrl.text.trim();
      tracker.endRecording(name, limit);
    }
  }
}
