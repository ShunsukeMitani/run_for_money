import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class AreaEditorScreen extends StatefulWidget {
  const AreaEditorScreen({super.key});

  @override
  State<AreaEditorScreen> createState() => _AreaEditorScreenState();
}

class _AreaEditorScreenState extends State<AreaEditorScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _playArea = [];
  List<List<LatLng>> _forbiddenAreas = [];
  
  final List<LatLng> _currentPolygon = [];
  String _editMode = 'PLAY_AREA'; // 'PLAY_AREA' または 'FORBIDDEN'

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    var doc = await FirebaseFirestore.instance.collection('games').doc('game_001').get();
    if (doc.exists && doc.data()!.containsKey('areaSettings')) {
      var settings = doc['areaSettings'];
      setState(() {
        if (settings['playArea'] != null) {
          _playArea = (settings['playArea'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList();
        }
        if (settings['forbiddenAreas'] != null) {
          // ★修正: Firestoreの仕様に合わせ、Mapから 'points' を取り出す形に変更
          _forbiddenAreas = (settings['forbiddenAreas'] as List).map((areaObj) {
            var pts = areaObj['points'] as List;
            return pts.map((p) => LatLng(p['lat'], p['lng'])).toList();
          }).toList();
        }
      });
    }
    
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _mapController.move(LatLng(p.latitude, p.longitude), 16);
    } catch(e) {}
  }

  void _saveAreas() async {
    List<Map<String, double>> playAreaJson = _playArea.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    
    // ★修正: 配列の配列ではなく、Mapのリストとして保存する（Firestoreのエラー回避）
    List<Map<String, dynamic>> forbiddenJson = _forbiddenAreas.map((area) {
      return {
        'points': area.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList()
      };
    }).toList();

    await FirebaseFirestore.instance.collection('games').doc('game_001').set({
      'areaSettings': {
        'playArea': playAreaJson,
        'forbiddenAreas': forbiddenJson,
      }
    }, SetOptions(merge: true));

    if(mounted){
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("エリア設定を保存しました")));
    }
  }

  void _handleTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      _currentPolygon.add(latlng);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("エリア詳細設定", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            onPressed: _saveAreas,
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[800],
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ChoiceChip(
                  label: const Text("基本エリア(外枠)"),
                  selected: _editMode == 'PLAY_AREA',
                  onSelected: (v) => setState(() { _editMode = 'PLAY_AREA'; _currentPolygon.clear(); }),
                  selectedColor: Colors.blueAccent,
                ),
                ChoiceChip(
                  label: const Text("進入禁止エリア"),
                  selected: _editMode == 'FORBIDDEN',
                  onSelected: (v) => setState(() { _editMode = 'FORBIDDEN'; _currentPolygon.clear(); }),
                  selectedColor: Colors.redAccent,
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(35.6812, 139.7671),
                initialZoom: 16,
                onTap: _handleTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.run_for_money', 
                ),
                PolygonLayer(
                  polygons: [
                    if (_playArea.isNotEmpty)
                      Polygon(
                        points: _playArea,
                        color: Colors.blue.withOpacity(0.1),
                        borderColor: Colors.blueAccent,
                        borderStrokeWidth: 3,
                      ),
                    for (var area in _forbiddenAreas)
                      Polygon(
                        points: area,
                        color: Colors.red.withOpacity(0.3),
                        borderColor: Colors.redAccent,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    if (_currentPolygon.isNotEmpty)
                      Polyline(
                        points: _currentPolygon,
                        color: _editMode == 'PLAY_AREA' ? Colors.cyan : Colors.orangeAccent,
                        strokeWidth: 3,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: _currentPolygon.map((p) => Marker(
                    point: p,
                    width: 10,
                    height: 10,
                    child: const CircleAvatar(backgroundColor: Colors.white),
                  )).toList(),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.undo, color: Colors.white),
                    label: const Text("1つ戻る", style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      if (_currentPolygon.isNotEmpty) {
                        setState(() => _currentPolygon.removeLast());
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text("エリア確定", style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      setState(() {
                        if (_currentPolygon.length >= 3) {
                          if (_editMode == 'PLAY_AREA') {
                            _playArea = List.from(_currentPolygon);
                          } else {
                            _forbiddenAreas.add(List.from(_currentPolygon));
                          }
                          _currentPolygon.clear();
                          _saveAreas(); // 確定時に自動保存
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("エリアを作るには3箇所以上タップしてください", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_editMode == 'FORBIDDEN')
            SafeArea( // ★魔法のバリアを追加！これでナビゲーションバーを避けます
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10.0), // ★少しだけ上に隙間を空けて押しやすくする
                child: TextButton(
                  onPressed: () {
                    setState(() => _forbiddenAreas.clear());
                    _saveAreas();
                  },
                  child: const Text("進入禁止エリアをすべて削除", style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}