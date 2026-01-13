// Paste this code into lib/services/music_manager.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_data.dart'; // Import your model

class MusicManager {
  static final MusicManager _instance = MusicManager._internal();
  factory MusicManager() => _instance;
  MusicManager._internal();

  List<SongData> allSongs = [];
  
  Future<void> saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(allSongs.map((e) => e.toJson()).toList());
    await prefs.setString('saved_songs', encoded);
  }

  Future<void> loadSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString('saved_songs');
    if (encoded != null) {
      final List<dynamic> decoded = jsonDecode(encoded);
      allSongs = decoded.map((e) => SongData.fromJson(e)).toList();
    }
  }

  List<SongData> getUnclassified() => 
      allSongs.where((s) => s.speed == SongSpeed.unclassified).toList();

  List<SongData> getBySpeed(SongSpeed speed) => 
      allSongs.where((s) => s.speed == speed).toList();
}