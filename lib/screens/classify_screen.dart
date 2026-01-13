// Paste this code into lib/screens/classify_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/music_manager.dart';
import '../models/song_data.dart';

class ClassifyScreen extends StatefulWidget {
  const ClassifyScreen({super.key});

  @override
  State<ClassifyScreen> createState() => _ClassifyScreenState();
}

class _ClassifyScreenState extends State<ClassifyScreen> {
  bool _isSwipeMode = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSwipeMode ? "Swipe Mode" : "Library Manager"),
        actions: [
          IconButton(
            tooltip: _isSwipeMode ? "Switch to List View" : "Switch to Swipe View",
            icon: Icon(_isSwipeMode ? Icons.list_alt : Icons.swipe),
            onPressed: () {
              setState(() {
                _isSwipeMode = !_isSwipeMode;
              });
            },
          ),
        ],
      ),
      body: _isSwipeMode 
        ? const SwipeClassifierView() 
        : const ListClassifierView(),
    );
  }
}

class ListClassifierView extends StatefulWidget {
  const ListClassifierView({super.key});

  @override
  State<ListClassifierView> createState() => _ListClassifierViewState();
}

class _ListClassifierViewState extends State<ListClassifierView> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false; // Added loading state

  // This function handles the entire process: Permissions -> Picking -> Saving
  Future<void> _pickDirectory() async {
    // 1. Request Permission
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
         if (await Permission.audio.request().isGranted || await Permission.storage.request().isGranted) {
            status = PermissionStatus.granted;
         }
      }
    } else {
      status = await Permission.storage.request();
    }

    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Permission Denied")));
      return;
    }

    // 2. Open Picker
    setState(() => _isLoading = true); 
    
    // We don't call _openFilePicker anymore, we do it right here:
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      List<SongData> newSongs = [];
      
      try {
        final files = dir.listSync(recursive: true);
        for (var file in files) {
          if (file is File) {
            String ext = p.extension(file.path).toLowerCase();
            if (ext == '.mp3' || ext == '.m4a' || ext == '.wav') {
              // Check if song already exists to avoid duplicates
              bool exists = MusicManager().allSongs.any((s) => s.path == file.path);
              if (!exists) {
                newSongs.add(SongData(path: file.path));
              }
            }
          }
        }
      } catch (e) {
        print("Error reading directory: $e");
      }

      if (newSongs.isNotEmpty) {
        // Add new songs to our list
        MusicManager().allSongs.addAll(newSongs); 
        await MusicManager().saveSongs();
        
        // Refresh the UI
        setState(() {}); 
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Added ${newSongs.length} new songs!")),
          );
        }
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No new songs found.")));
        }
      }
    }
    setState(() => _isLoading = false); 
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          // Header with Search and Add Button
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickDirectory, // Disable if loading
                  icon: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                  label: const Text("Add Folder"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                )
              ],
            ),
          ),
          
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: "Unsorted", icon: Icon(Icons.help_outline)),
              Tab(text: "Slow", icon: Icon(Icons.speed, color: Colors.teal)),
              Tab(text: "Medium", icon: Icon(Icons.speed, color: Colors.purple)),
              Tab(text: "Fast", icon: Icon(Icons.speed, color: Colors.red)),
            ],
          ),

          Expanded(
            child: TabBarView(
              children: [
                _buildSongList(SongSpeed.unclassified),
                _buildSongList(SongSpeed.slow),
                _buildSongList(SongSpeed.medium),
                _buildSongList(SongSpeed.fast),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(SongSpeed category) {
    // 1. Filter by Category
    List<SongData> songs = MusicManager().allSongs
        .where((s) => s.speed == category)
        .toList();

    // 2. Filter by Search Query
    if (_searchQuery.isNotEmpty) {
      songs = songs.where((s) => 
        p.basename(s.path).toLowerCase().contains(_searchQuery)
      ).toList();
    }

    if (songs.isEmpty) {
      return const Center(child: Text("No songs here.", style: TextStyle(color: Colors.white38)));
    }

    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final fileName = p.basename(song.path);

        return Card(
          color: Colors.grey[900],
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            trailing: PopupMenuButton<SongSpeed>(
              icon: const Icon(Icons.more_vert),
              onSelected: (SongSpeed newSpeed) {
                setState(() {
                  song.speed = newSpeed;
                  MusicManager().saveSongs();
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Moved to ${newSpeed.name.toUpperCase()}"),
                    duration: const Duration(milliseconds: 800),
                  )
                );
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<SongSpeed>>[
                const PopupMenuItem(value: SongSpeed.slow, child: Text("Move to Slow")),
                const PopupMenuItem(value: SongSpeed.medium, child: Text("Move to Medium")),
                const PopupMenuItem(value: SongSpeed.fast, child: Text("Move to Fast")),
                const PopupMenuDivider(),
                const PopupMenuItem(value: SongSpeed.unclassified, child: Text("Reset (Unsorted)", style: TextStyle(color: Colors.grey))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SwipeClassifierView extends StatefulWidget {
  const SwipeClassifierView({super.key});

  @override
  State<SwipeClassifierView> createState() => _SwipeClassifierViewState();
}

class _SwipeClassifierViewState extends State<SwipeClassifierView> {
  final AudioPlayer _player = AudioPlayer();
  List<SongData> _queue = [];
  SongData? _currentSong;

  @override
  void initState() {
    super.initState();
    // Only fetch UNCLASSIFIED songs for swiping
    _queue = MusicManager().getUnclassified();
    _loadNext();
  }

  Future<void> _loadNext() async {
    if (_queue.isEmpty) {
      setState(() => _currentSong = null);
      _player.stop();
      return;
    }

    _currentSong = _queue.first;
    setState(() {});

    try {
      await _player.setFilePath(_currentSong!.path);
      // Play 15 seconds in
      await _player.seek(const Duration(seconds: 15)); 
      _player.play();
    } catch (e) {
      // Auto-skip corrupted files
      _classify(SongSpeed.unclassified); 
    }
  }

  void _classify(SongSpeed speed) {
    if (_currentSong == null) return;
    
    _currentSong!.speed = speed;
    MusicManager().saveSongs();
    
    setState(() {
      _queue.removeAt(0);
    });
    _loadNext();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSong == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
            SizedBox(height: 20),
            Text("All caught up!", style: TextStyle(fontSize: 20)),
            SizedBox(height: 10),
            Text("Switch to List View to manage existing songs.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Center(
      child: GestureDetector(
        onPanEnd: (details) {
          double dx = details.velocity.pixelsPerSecond.dx;
          double dy = details.velocity.pixelsPerSecond.dy;

          if (dx.abs() > dy.abs()) {
            if (dx > 0) {
              _classify(SongSpeed.slow);
            } else {
              _classify(SongSpeed.fast);
            }
          } else {
            if (dy < 0) {
              _classify(SongSpeed.medium);
            }
          }
        },
        child: Container(
          height: 450,
          width: 320,
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(blurRadius: 15, color: Colors.black45)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_note, size: 100, color: Colors.white),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  p.basename(_currentSong!.path),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 50),
              // Visual Guide
              Column(
                children: [
                  const Icon(Icons.keyboard_arrow_up, color: Colors.purpleAccent),
                  const Text("Medium", style: TextStyle(color: Colors.purpleAccent)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Column(
                          children: const [
                            Icon(Icons.keyboard_arrow_left, color: Colors.redAccent),
                            Text("Fast", style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Column(
                          children: const [
                            Icon(Icons.keyboard_arrow_right, color: Colors.tealAccent),
                            Text("Slow", style: TextStyle(color: Colors.tealAccent)),
                          ],
                        ),
                      ),
                    ],
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}