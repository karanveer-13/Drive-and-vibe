// Paste this code into lib/screens/drive_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/music_manager.dart';
import '../models/song_data.dart';

enum DriveMode { auto, slow, medium, fast }

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _positionStream;
  
  // Speed & Smoothing
  double _currentSpeedKmh = 0.0;
  
  // State Logic
  SongSpeed _currentMood = SongSpeed.slow;
  DriveMode _driveMode = DriveMode.auto;
  RangeValues _speedThresholds = const RangeValues(30, 80);
  
  // NEW: Timer for the "Cooldown" logic
  Timer? _downshiftTimer;
  bool _isDownshiftPending = false; 

  bool _isFading = false;

  // --- NEW: History Map to track last 3 songs per mood ---
  final Map<SongSpeed, List<String>> _recentHistory = {
    SongSpeed.slow: [],
    SongSpeed.medium: [],
    SongSpeed.fast: [],
    SongSpeed.unclassified: [],
  };

  @override
  void initState() {
    super.initState();
    _initLocation();
    
    // Start music after brief UI settle
    Future.delayed(const Duration(milliseconds: 500), () {
      _playNextSong(fadeIn: false);
    });

    // Listen for song completion
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // When song ends, this naturally picks a song based on the _currentMood
        _playNextSong(); 
      }
    });
  }

  Future<void> _initLocation() async {
    await Permission.location.request();
    
    LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: true,
        intervalDuration: const Duration(milliseconds: 500),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position? position) {
        if (position != null) {
          double instantaneousSpeed = position.speed * 3.6; 
          if (instantaneousSpeed < 0) instantaneousSpeed = 0;
          
          if (mounted) {
            setState(() {
              if (instantaneousSpeed < 1.0) {
                 _currentSpeedKmh = 0.0;
              } else {
                 _currentSpeedKmh = (_currentSpeedKmh * 0.8) + (instantaneousSpeed * 0.2);
              }
            });

            if (_driveMode == DriveMode.auto) {
              _calculateAutoMood(_currentSpeedKmh);
            }
          }
        }
      });
  }

  void _calculateAutoMood(double speed) {
    SongSpeed targetMood;
    
    if (speed < _speedThresholds.start) {
      targetMood = SongSpeed.slow;
    } else if (speed < _speedThresholds.end) {
      targetMood = SongSpeed.medium;
    } else {
      targetMood = SongSpeed.fast;
    }

    if (targetMood == _currentMood) {
      _cancelDownshiftTimer();
      return;
    }

    if (targetMood.index > _currentMood.index) {
      // --- UPSHIFT ---
      _cancelDownshiftTimer();
      _changeMood(targetMood, forcePlay: true);
      
    } else {
      // --- DOWNSHIFT ---
      if (_downshiftTimer == null || !_downshiftTimer!.isActive) {
        print("Downshift detected. Starting 45s timer...");
        _downshiftTimer = Timer(const Duration(seconds: 45), () {
          if (mounted) {
            print("45s passed. Committing downshift to $targetMood");
            _changeMood(targetMood, forcePlay: false);
          }
        });
      }
    }
  }

  void _cancelDownshiftTimer() {
    if (_downshiftTimer != null && _downshiftTimer!.isActive) {
      _downshiftTimer!.cancel();
      print("Speed recovered. Downshift cancelled.");
    }
  }

  void _changeMood(SongSpeed newMood, {required bool forcePlay}) {
    setState(() => _currentMood = newMood);
    
    if (forcePlay) {
      print("Mood UP: Fading to new track immediately.");
      _playNextSong(fadeIn: true);
    } else {
      print("Mood DOWN: Mood updated, but waiting for current song to finish.");
    }
  }

  void _onModeChanged(DriveMode? newMode) {
    if (newMode == null) return;
    setState(() => _driveMode = newMode);
    _cancelDownshiftTimer(); 

    if (newMode == DriveMode.auto) {
      _calculateAutoMood(_currentSpeedKmh);
    } else {
      if (newMode == DriveMode.slow) _changeMood(SongSpeed.slow, forcePlay: true);
      if (newMode == DriveMode.medium) _changeMood(SongSpeed.medium, forcePlay: true);
      if (newMode == DriveMode.fast) _changeMood(SongSpeed.fast, forcePlay: true);
    }
  }

  // --- CHANGED: Smart Song Selection Logic ---
  Future<void> _playNextSong({bool fadeIn = false}) async {
    if (_isFading) return; 

    // 1. Get raw candidates
    List<SongData> candidates = MusicManager().getBySpeed(_currentMood);
    
    // Fallback if empty
    if (candidates.isEmpty) candidates = MusicManager().allSongs;
    
    if (candidates.isEmpty) {
      print("No songs found at all!");
      return;
    }

    // 2. NEW: Filter out recently played songs for this mood
    List<String> recentList = _recentHistory[_currentMood] ?? [];
    
    List<SongData> availableSongs = candidates.where((song) {
      // Keep song ONLY if it is NOT in the recent list
      return !recentList.contains(song.path);
    }).toList();

    // 3. Safety Fallback: If we filtered out ALL songs (e.g. you only have 2 slow songs),
    // then reset and play any candidate to avoid silence.
    if (availableSongs.isEmpty) {
      availableSongs = candidates;
    }

    // 4. Pick Random Song
    final randomSong = availableSongs[Random().nextInt(availableSongs.length)];

    // 5. NEW: Update History
    _addToHistory(_currentMood, randomSong.path);

    // 6. Play
    if (fadeIn && _player.playing) {
      await _crossFadeTo(randomSong.path);
    } else {
      await _player.setFilePath(randomSong.path);
      _player.play();
    }
  }

  // --- NEW: Helper to manage history size ---
  void _addToHistory(SongSpeed mood, String path) {
    // Add new song to the end
    _recentHistory[mood]?.add(path);
    
    // If we have more than 3, remove the oldest (first one)
    if ((_recentHistory[mood]?.length ?? 0) > 3) {
      _recentHistory[mood]?.removeAt(0);
    }
  }
  
  Future<void> _crossFadeTo(String newPath) async {
    _isFading = true;
    
    double startVolume = _player.volume;
    for (double v = startVolume; v > 0; v -= 0.1) {
      if (v < 0) v = 0;
      await _player.setVolume(v);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _player.pause();

    await _player.setFilePath(newPath);
    _player.play();

    for (double v = 0; v <= 1.0; v += 0.1) {
      await _player.setVolume(v);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _isFading = false;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _downshiftTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Drive Mode"),
      ),
      body: AnimatedContainer(
        duration: const Duration(seconds: 2),
        curve: Curves.easeInOut,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _getGradientColors(),
          )
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "${_currentSpeedKmh.toStringAsFixed(0)} km/h",
                    style: const TextStyle(fontSize: 70, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      "CURRENT MOOD: ${_currentMood.name.toUpperCase()}",
                      style: const TextStyle(fontSize: 18, letterSpacing: 1.5, color: Colors.white),
                    ),
                  ),
                ],
              ),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Mode:", style: TextStyle(color: Colors.white70)),
                        DropdownButton<DriveMode>(
                          value: _driveMode,
                          dropdownColor: Colors.grey[900],
                          style: const TextStyle(color: Colors.white),
                          underline: Container(),
                          items: DriveMode.values.map((mode) {
                            return DropdownMenuItem(
                              value: mode,
                              child: Text(mode.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                          onChanged: _onModeChanged,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    if (_driveMode == DriveMode.auto) ...[
                      const Text("Speed Thresholds (Slow / Med / Fast)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      RangeSlider(
                        values: _speedThresholds,
                        min: 0,
                        max: 150,
                        divisions: 15,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        labels: RangeLabels(
                          "${_speedThresholds.start.round()} km/h", 
                          "${_speedThresholds.end.round()} km/h"
                        ),
                        onChanged: (values) {
                          setState(() => _speedThresholds = values);
                        },
                      ),
                    ],

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StreamBuilder<PlayerState>(
                          stream: _player.playerStateStream,
                          builder: (context, snapshot) {
                            final playerState = snapshot.data;
                            final playing = playerState?.playing ?? false;
                            return IconButton(
                              iconSize: 64,
                              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                              onPressed: () {
                                if (playing) {
                                  _player.pause();
                                } else {
                                  _player.play();
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(width: 30),
                        IconButton(
                          iconSize: 50,
                          icon: const Icon(Icons.skip_next, color: Colors.white),
                          onPressed: () => _playNextSong(fadeIn: true),
                        ),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientColors() {
    switch (_currentMood) {
      case SongSpeed.fast:
        return [Colors.redAccent, Colors.deepOrange];
      case SongSpeed.medium:
        return [Colors.blueAccent, Colors.purpleAccent];
      case SongSpeed.slow:
        return [Colors.teal, Colors.green];
      default:
        return [Colors.grey, Colors.black];
    }
  }
}