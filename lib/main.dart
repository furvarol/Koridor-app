import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/corridors_screen.dart';
import 'screens/drive_screen.dart';
import 'pip.dart';
import 'screens/history_screen.dart';
import 'screens/pip_view.dart';
import 'tracker.dart';

final tracker = Tracker();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  await tracker.init();
  Pip.init();
  // Takip açıkken uygulamadan çıkınca hız PiP penceresinde görünsün.
  tracker.addListener(() => Pip.setAutoEnter(tracker.running));
  runApp(const KoridorApp());
}

class KoridorApp extends StatelessWidget {
  const KoridorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koridor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E6FD9),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Pip.active,
      builder: (context, inPip, _) => inPip ? const PipView() : _full(),
    );
  }

  Widget _full() {
    final pages = const [DriveScreen(), CorridorsScreen(), HistoryScreen()];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Sürüş'),
          NavigationDestination(icon: Icon(Icons.alt_route), label: 'Koridorlar'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Geçmiş'),
        ],
      ),
    );
  }
}
