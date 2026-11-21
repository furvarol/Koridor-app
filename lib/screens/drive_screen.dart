import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../live.dart';
import '../main.dart';
import '../pip.dart';
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
        IconButton(
          tooltip: t.voiceOn ? 'Sesli uyarıları kapat' : 'Sesli uyarıları aç',
          icon: Icon(t.voiceOn ? Icons.volume_up : Icons.volume_off,
              color: t.voiceOn ? null : Colors.redAccent),
          onPressed: () => t.setVoice(!t.voiceOn),
        ),
        IconButton(
          tooltip: 'Küçük pencerede göster',
          icon: const Icon(Icons.picture_in_picture_alt),
          onPressed: () async {
            if (!await Pip.enter() && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bu cihazda resim içinde resim açılamadı.')));
            }
          },
        ),
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
    final run = t.primary!;
    final c = run.corridor;
    final others = t.others;
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
          if (over || near) _MaxBanner(allowed: allowed, over: over),
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
            '${_fmt(t.elapsed)}  •  ${(t.distanceM / 1000).toStringAsFixed(1)} / ${(run.lengthM / 1000).toStringAsFixed(1)} km',
            style: style.bodySmall,
          ),
          for (final o in others)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${o.corridor.name}: ort. ${o.avgKmh(DateTime.now()).round()}, kalan ${(o.remainingM / 1000).toStringAsFixed(1)} km',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Limit aşıldığında (ya da yaklaşıldığında) koridorun sonuna kadar
/// ortalamayı limite indirmek için gidilebilecek en yüksek hız.
class _MaxBanner extends StatelessWidget {
  final double allowed;
  final bool over;
  const _MaxBanner({required this.allowed, required this.over});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    final impossible = allowed <= 0;
    final c = over ? Colors.redAccent : Colors.orangeAccent;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c),
      ),
      child: Column(
        children: [
          Text(impossible ? 'LİMİT ALTINA İNİLEMEZ' : 'SONA KADAR EN FAZLA',
              style: style.labelMedium?.copyWith(color: c)),
          Text(
            impossible ? 'Mümkün olduğunca yavaşla' : Live.allowedText(allowed),
            style: (impossible ? style.titleMedium : style.headlineMedium)
                ?.copyWith(color: c, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Text('Koridor kaydediliyor', style: style.titleMedium),
          ],
        ),
        const Spacer(),
        Text('ORTALAMA', style: style.labelMedium),
        Text('${t.recordingAvgKmh.round()}',
            style: style.displayLarge?.copyWith(fontSize: 120, fontWeight: FontWeight.w600)),
        Text('km/s', style: style.titleMedium),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat('Anlık', '${t.currentKmh.round()}'),
            _Stat('Mesafe', '${(t.recordingLengthM / 1000).toStringAsFixed(2)} km'),
            _Stat('Süre', _fmtDur(t.recordingElapsed)),
          ],
        ),
        const SizedBox(height: 12),
        Text('Koridor bitiş tabelasını geçince "Bitiş" bas.',
            textAlign: TextAlign.center, style: style.bodyMedium?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

String _fmtDur(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

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
                  // Canlı bildirim (durum çubuğu çipi) için izinler.
                  await Live.requestPermission();
                  if (await Live.canPromote() == false && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Durum çubuğunda hız için "Canlı güncellemeler" iznini aç.'),
                      action: SnackBarAction(label: 'Ayarlar', onPressed: Live.openSettings),
                    ));
                  }
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
                onPressed: t.running
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
    // Çıkış tabelası konumu bu an; diyalog açıkken iz uzamaz.
    tracker.markRecordingEnd();
    final m = tracker.findOfficialMatch();
    if (m != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => _VerifyDialog(m),
      );
      if (choice == null) {
        tracker.resumeRecording();
        return;
      }
      await tracker.applyVerification(m, finish: choice == 'only');
      if (choice == 'only' || !context.mounted) return;
    }
    if (!context.mounted) return;
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
    if (ok == null) {
      tracker.resumeRecording(); // diyalog kapatıldı, kayıt sürüyor
      return;
    }
    if (ok == true) {
      final limit = int.tryParse(limitCtrl.text) ?? 110;
      final name = nameCtrl.text.trim().isEmpty ? 'Koridor ${tracker.corridors.length + 1}' : nameCtrl.text.trim();
      tracker.endRecording(name, limit);
    }
  }
}

/// Elle işaretlenen giriş/çıkış tabelalarını resmi koridorla karşılaştırır.
class _VerifyDialog extends StatelessWidget {
  final VerifyMatch m;
  const _VerifyDialog(this.m);

  @override
  Widget build(BuildContext context) {
    final c = m.corridor;
    final style = Theme.of(context).textTheme;
    final color = m.ok ? Colors.greenAccent : Colors.orangeAccent;
    String d(double v) => v < 1000 ? '${v.round()} m' : '${(v / 1000).toStringAsFixed(1)} km';
    return AlertDialog(
      title: const Text('Resmi koridorla karşılaştır'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: style.titleMedium),
          const SizedBox(height: 8),
          Text('Giriş tabelası farkı: ${d(m.startDiffM)}'),
          Text('Çıkış tabelası farkı: ${d(m.endDiffM)}'),
          Text('Uzunluk: senin ${(m.recordedLenM / 1000).toStringAsFixed(1)} km, '
              'bakanlık ${(c.lengthM / 1000).toStringAsFixed(1)} km'),
          const SizedBox(height: 12),
          Text(
            m.ok
                ? 'DOĞRULANDI (iki fark da ${Tracker.verifyToleranceM.round()} m içinde)'
                : 'DOĞRULANMADI (fark ${Tracker.verifyToleranceM.round()} m\'den fazla)',
            style: style.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        TextButton(
            onPressed: () => Navigator.pop(context, 'both'),
            child: const Text('İşaretle + elle kaydı sakla')),
        FilledButton(onPressed: () => Navigator.pop(context, 'only'), child: const Text('İşaretle')),
      ],
    );
  }
}
