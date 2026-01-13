// Paste this code into lib/models/song_data.dart

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