// Paste this code into lib/screens/home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/music_manager.dart';
import '../models/song_data.dart';
import 'drive_screen.dart';
import 'classify_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await MusicManager().loadSongs();

    final prefs = await SharedPreferences.getInstance();
    bool assetsInstalled = prefs.getBool('assets_installed') ?? false;

    if (!assetsInstalled) {
      await _installDefaultAssets();
      await prefs.setBool('assets_installed', true);
      await MusicManager().loadSongs(); 
    }

    setState(() => _isReady = true);
  }

  Future<void> _installDefaultAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/DefaultMusic');
    if (!await musicDir.exists()) await musicDir.create();

    final Map<SongSpeed, List<String>> defaultTracks = {
      SongSpeed.fast:   ['Barbaadiyan.mp3','dhurandhar-title-track.mp3','I Hate Luv Storys.mp3','Just Keep Watching (From F1 The Movie).mp3','like JENNIE.mp3','naal-nachna-from-dhurandhar.mp3','run-down-the-city-monica.mp3','the-ba-ds-of-bollywood-sajna-tu-baimaan.mp3'], // Update with your actual filenames
      SongSpeed.medium: ['Aadat Se Majboor.mp3','Alcoholic.mp3','Allah Maaf Kare.mp3','bandook-meri-laila-from-a-gentleman-feat-raftaar.mp3','Haaye Oye.mp3','Khadke Glassy.mp3','Lucky Tu Lucky Me.mp3','Popular (The Idol Vol. 1 (Music from the HBO Original Series)).mp3','STAY.mp3','Symmetry (feat. Karan Aujla) (Remix).mp3'], 
      SongSpeed.slow:   ['Haareya.mp3','Ishq Bulaava.mp3','Jaanam (From Bad Newz).mp3','Nain Ta Heere.mp3','Nazar Na Lag Jaaye (From Stree).mp3','Often (Kygo Remix).mp3','OH GIRL YOURE MINE.mp3'], 
    };

    List<SongData> newSongs = [];

    for (var speed in defaultTracks.keys) {
      String folderName = speed.name;
      List<String> files = defaultTracks[speed]!;

      for (var fileName in files) {
        try {
          final byteData = await rootBundle.load('assets/$folderName/$fileName');
          final file = File('${musicDir.path}/$fileName');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
          newSongs.add(SongData(path: file.path, speed: speed));
        } catch (e) {
          print("Error installing asset $fileName: $e");
        }
      }
    }

    MusicManager().allSongs.addAll(newSongs);
    await MusicManager().saveSongs();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Drive & Vibe")),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MenuButton(
              icon: Icons.drive_eta,
              label: "DRIVE",
              color: Colors.green,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriveScreen())),
            ),
            _MenuButton(
              icon: Icons.sort,
              label: "CLASSIFY",
              color: Colors.orange,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassifyScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        width: 150,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}