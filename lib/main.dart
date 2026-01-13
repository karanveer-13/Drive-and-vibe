import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle; // To read assets
import 'package:path_provider/path_provider.dart';      // To find save location
import 'package:just_audio_background/just_audio_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drive & Vibe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomeScreen(),
    );
  }
}

// --- DATA MODELS ---

enum SongSpeed { slow, medium, fast, unclassified }

class SongData {
  final String path;
  SongSpeed speed;

  SongData({required this.path, this.speed = SongSpeed.unclassified});

  Map<String, dynamic> toJson() => {
        'path': path,
        'speed': speed.index,
      };

  factory SongData.fromJson(Map<String, dynamic> json) {
    return SongData(
      path: json['path'],
      speed: SongSpeed.values[json['speed']],
    );
  }
}

// --- SERVICES ---

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

// --- SCREEN 1: DIRECTORY SELECTION ---

class DirectorySelectionScreen extends StatefulWidget {
  const DirectorySelectionScreen({super.key});

  @override
  State<DirectorySelectionScreen> createState() => _DirectorySelectionScreenState();
}

class _DirectorySelectionScreenState extends State<DirectorySelectionScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

// Inside _DirectorySelectionScreenState

  Future<void> _loadExistingData() async {
    await MusicManager().loadSongs();

    // Check if we have already installed the default assets
    final prefs = await SharedPreferences.getInstance();
    bool assetsInstalled = prefs.getBool('assets_installed') ?? false;

    if (!assetsInstalled) {
      // Show loading indicator while copying
      setState(() => _isLoading = true);
      await _installDefaultAssets();
      await prefs.setBool('assets_installed', true);
      
      // Reload the manager to include the new files
      await MusicManager().loadSongs();
      setState(() => _isLoading = false);
    }

    // If we have any songs (user OR default), go to home
    if (MusicManager().allSongs.isNotEmpty) {
       _navigateToHome();
    }
  }

  Future<void> _installDefaultAssets() async {
    // 1. Get a permanent place on the phone to store these files
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/DefaultMusic');
    if (!await musicDir.exists()) {
      await musicDir.create();
    }

    // 2. Define your assets (You must manually list file names or use a JSON manifest)
    // Flutter unfortunately cannot list assets dynamically at runtime easily.
    // The easiest way is to list them here:
    
    final Map<SongSpeed, List<String>> defaultTracks = {
      SongSpeed.fast:   [ 'Barbaadiyan.mp3', 'dhurandhar-title-track.mp3', 'I Hate Luv Storys.mp3', 'Just Keep Watching (From F1 The Movie).mp3', 'like JENNIE.mp3', 'naal-nachna-from-dhurandhar.mp3', 'run-down-the-city-monica.mp3', 'the-ba-ds-of-bollywood-sajna-tu-baimaan.mp3'], // Filenames in assets/fast/
      SongSpeed.medium: ['Aadat Se Majboor.mp3', 'Alcoholic.mp3', 'Allah Maaf Kare.mp3', 'bandook-meri-laila-from-a-gentleman-feat-raftaar.mp3', 'Haaye Oye.mp3', 'Khadke Glassy.mp3', 'Lucky Tu Lucky Me.mp3', 'Popular (The Idol Vol. 1 (Music from the HBO Original Series)).mp3', 'STAY.mp3', 'Symmetry (feat. Karan Aujla) (Remix).mp3'], // Filenames in assets/medium/
      SongSpeed.slow:   ['Haareya.mp3', 'Ishq Bulaava.mp3', 'Jaanam (From Bad Newz).mp3', 'Nain Ta Heere.mp3', 'Nazar Na Lag Jaaye (From Stree).mp3', 'Often (Kygo Remix).mp3', 'OH GIRL YOURE MINE.mp3'], // Filenames in assets/slow/
    };

    List<SongData> newSongs = [];

    // 3. Loop through and copy files
    for (var speed in defaultTracks.keys) {
      String folderName = speed.name; // "fast", "medium", "slow"
      List<String> files = defaultTracks[speed]!;

      for (var fileName in files) {
        try {
          // Read from Asset Bundle
          final byteData = await rootBundle.load('assets/$folderName/$fileName');
          
          // Write to Phone Storage
          final file = File('${musicDir.path}/$fileName');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

          // Add to MusicManager
          // Note: We immediately classify them!
          newSongs.add(SongData(path: file.path, speed: speed));
          print("Installed default track: $fileName as $speed");
        } catch (e) {
          print("Error installing asset $fileName: $e");
        }
      }
    }

    // 4. Merge with existing songs (if any) and save
    MusicManager().allSongs.addAll(newSongs);
    await MusicManager().saveSongs();
  }
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
    setState(() => _isLoading = true); // Make sure you define bool _isLoading = false; in your state class
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
        // FIX: Use addAll, do not use =
        MusicManager().allSongs.addAll(newSongs); 
        await MusicManager().saveSongs();
        
        // FIX: Do not navigate away, just refresh the current screen
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
    // Remove the loading state if you added that variable, otherwise ignore
    // setState(() => _isLoading = false); 
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (context) => const HomeScreen())
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading 
        ? const CircularProgressIndicator()
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text("Select your Music Folder", style: TextStyle(fontSize: 20)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _pickDirectory,
                child: const Text("Browse"),
              ),
              const SizedBox(height: 10),
              // Helper reset button if needed
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  MusicManager().allSongs = [];
                  setState(() {});
                }, 
                child: const Text("Reset Data", style: TextStyle(color: Colors.grey))
              )
            ],
          ),
      ),
    );
  }
}

// --- SCREEN 2: HOME / OPTIONS ---

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
    // 1. Load any saved data
    await MusicManager().loadSongs();

    // 2. Check and Install Default Assets if needed
    final prefs = await SharedPreferences.getInstance();
    bool assetsInstalled = prefs.getBool('assets_installed') ?? false;

    if (!assetsInstalled) {
      await _installDefaultAssets();
      await prefs.setBool('assets_installed', true);
      await MusicManager().loadSongs(); // Reload to see new files
    }

    setState(() => _isReady = true);
  }

  // ... (Paste the _installDefaultAssets function from the previous step here) ...
  Future<void> _installDefaultAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/DefaultMusic');
    if (!await musicDir.exists()) await musicDir.create();

    // YOUR ASSET LIST HERE
    final Map<SongSpeed, List<String>> defaultTracks = {
      SongSpeed.fast:   [ 'Barbaadiyan.mp3', 'dhurandhar-title-track.mp3', 'I Hate Luv Storys.mp3', 'Just Keep Watching (From F1 The Movie).mp3', 'like JENNIE.mp3', 'naal-nachna-from-dhurandhar.mp3', 'run-down-the-city-monica.mp3', 'the-ba-ds-of-bollywood-sajna-tu-baimaan.mp3' ], // Update with your actual files
      SongSpeed.medium: ['Aadat Se Majboor.mp3', 'Alcoholic.mp3', 'Allah Maaf Kare.mp3', 'bandook-meri-laila-from-a-gentleman-feat-raftaar.mp3', 'Haaye Oye.mp3', 'Khadke Glassy.mp3', 'Lucky Tu Lucky Me.mp3', 'Popular (The Idol Vol. 1 (Music from the HBO Original Series)).mp3', 'STAY.mp3', 'Symmetry (feat. Karan Aujla) (Remix).mp3'], 
      SongSpeed.slow:   ['Haareya.mp3', 'Ishq Bulaava.mp3', 'Jaanam (From Bad Newz).mp3', 'Nain Ta Heere.mp3', 'Nazar Na Lag Jaaye (From Stree).mp3', 'Often (Kygo Remix).mp3', 'OH GIRL YOURE MINE.mp3'], 
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

  // Logic to handle "Classify" click
  void _handleClassifyClick() {
     // If we have "User Songs" (unclassified), go to Classify
     // OR if the user just wants to manage the library.
     // But per your request: "Ask to choose folder first time"
     
     // We can check if the user has ever added a custom folder.
     // For simplicity, let's just go to the screen, and let THAT screen handle the "Add Folder" button.
     Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassifyScreen()));
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
              onTap: _handleClassifyClick,
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

// --- SCREEN 3: CLASSIFY (Dual Mode: Swipe & List) ---

class ClassifyScreen extends StatefulWidget {
  const ClassifyScreen({super.key});

  @override
  State<ClassifyScreen> createState() => _ClassifyScreenState();
}

class _ClassifyScreenState extends State<ClassifyScreen> {
  // Toggle State: true = Swipe Mode, false = List Mode
  bool _isSwipeMode = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSwipeMode ? "Swipe Mode" : "Library Manager"),
        actions: [
          // The Toggle Button
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
      // We use a key to force rebuild when switching modes to ensure data refreshes
      body: _isSwipeMode 
        ? const SwipeClassifierView() 
        : const ListClassifierView(),
    );
  }
}

// --- SUB-VIEW 1: THE SWIPE UI (Original Logic) ---

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

// --- SUB-VIEW 2: THE LIST EDITOR UI ---

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

// --- SCREEN 4: DRIVE MODE (FIXED & IMPROVED) ---

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
  bool _isDownshiftPending = false; // Just for debugging/visuals if needed

  bool _isFading = false;

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
        // at that specific moment.
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
              // Smooth the speed
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
    
    // 1. Determine what the mood SHOULD be based on speed
    if (speed < _speedThresholds.start) {
      targetMood = SongSpeed.slow;
    } else if (speed < _speedThresholds.end) {
      targetMood = SongSpeed.medium;
    } else {
      targetMood = SongSpeed.fast;
    }

    // 2. Compare with current mood
    if (targetMood == _currentMood) {
      // We are stable. Cancel any pending downshift timers.
      _cancelDownshiftTimer();
      return;
    }

    // 3. LOGIC: Compare intensities
    // We use the enum index: Slow(0) < Medium(1) < Fast(2)
    if (targetMood.index > _currentMood.index) {
      // --- UPSHIFT (Going Faster) ---
      // Logic: Change IMMEDIATELY. High energy demands instant response.
      _cancelDownshiftTimer();
      _changeMood(targetMood, forcePlay: true);
      
    } else {
      // --- DOWNSHIFT (Going Slower) ---
      // Logic: Wait 45 seconds before accepting this new reality.
      
      if (_downshiftTimer == null || !_downshiftTimer!.isActive) {
        print("Downshift detected. Starting 45s timer...");
        _downshiftTimer = Timer(const Duration(seconds: 45), () {
          if (mounted) {
            // Timer finished! The car has truly been slow for 45s.
            // Apply the new mood, but DO NOT interrupt the song (forcePlay: false).
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

  // LOGIC: Added 'forcePlay' parameter
  void _changeMood(SongSpeed newMood, {required bool forcePlay}) {
    setState(() => _currentMood = newMood);
    
    if (forcePlay) {
      // Case: Upshifting. Fade out old track, bring in the hype track NOW.
      print("Mood UP: Fading to new track immediately.");
      _playNextSong(fadeIn: true);
    } else {
      // Case: Downshifting. 
      // We updated the variable _currentMood above.
      // We do NOTHING else. The current song keeps playing.
      // When it finishes, the listener in initState will call _playNextSong(),
      // which will look at the NEW _currentMood and pick a slow song.
      print("Mood DOWN: Mood updated, but waiting for current song to finish.");
    }
  }

  void _onModeChanged(DriveMode? newMode) {
    if (newMode == null) return;
    setState(() => _driveMode = newMode);
    _cancelDownshiftTimer(); // Manual override kills any timers

    if (newMode == DriveMode.auto) {
      _calculateAutoMood(_currentSpeedKmh);
    } else {
      // Manual mode always forces immediate change
      if (newMode == DriveMode.slow) _changeMood(SongSpeed.slow, forcePlay: true);
      if (newMode == DriveMode.medium) _changeMood(SongSpeed.medium, forcePlay: true);
      if (newMode == DriveMode.fast) _changeMood(SongSpeed.fast, forcePlay: true);
    }
  }

  Future<void> _playNextSong({bool fadeIn = false}) async {
    if (_isFading) return; 

    List<SongData> candidates = MusicManager().getBySpeed(_currentMood);
    
    if (candidates.isEmpty) candidates = MusicManager().allSongs;
    
    if (candidates.isEmpty) {
      print("No songs found at all!");
      return;
    }

    final randomSong = candidates[Random().nextInt(candidates.length)];

    if (fadeIn && _player.playing) {
      await _crossFadeTo(randomSong.path);
    } else {
      await _player.setFilePath(randomSong.path);
      _player.play();
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
    _downshiftTimer?.cancel(); // Clean up timer
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
                          // Recalculate, but simple recalculation won't trigger downshift timer logic 
                          // if we just move sliders. 
                          // It's okay, next GPS update will catch it.
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