//テスト
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapScreen extends StatefulWidget {
  final String myRole;
  final String myName;
  // 'NORMAL', 'SELECT_AREA', 'PLACE_BOX', 'SELECT_LOCATION'
  final String initialMode;

  const MapScreen({
    super.key,
    required this.myRole,
    required this.myName,
    this.initialMode = 'NORMAL',
  });

  bool get isSelectionMode => initialMode != 'NORMAL';

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _myLocation = const LatLng(35.681236, 139.767125);
  bool _isFirstLocationUpdate = true; // 初回移動用
  double _currentHeading = 0.0;
  Timer? _positionTimer;
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _isSurrenderPossible = false;
  bool _isOutOfArea = false;
  bool _isConnected = true;

  bool? _prevOutOfAreaState;

  late String _editMode;
  List<LatLng> _tempAreaPoints = [];
  final List<Marker> _tempBoxMarkers = [];
  LatLng? _selectedSinglePoint;

  List<dynamic> _cachedSurrenderPoints = [];
  List<dynamic> _cachedCurrentAreaPoints = [];
  List<List<LatLng>> _cachedForbiddenAreas = []; 
  bool _cachedAllowSurrender = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialMode == 'SELECT_AREA') {
      _editMode = 'AREA';
    } else if (widget.initialMode == 'PLACE_BOX') {
      _editMode = 'BOX';
    } else if (widget.initialMode == 'SELECT_LOCATION') {
      _editMode = 'LOCATION';
    } else {
      _editMode = 'NONE';
    }

    _startTracking();
    FirebaseFirestore.instance
        .collection('.info')
        .doc('connected')
        .snapshots()
        .listen(
          (_) => setState(() => _isConnected = true),
          onError: (_) => setState(() => _isConnected = false),
        );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    _updatePosition();
    _positionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updatePosition(),
    );
  }

  Future<void> _updatePosition() async {
    try {
      Position p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      LatLng newLoc = LatLng(p.latitude, p.longitude);

      if (mounted) {
        setState(() {
          _myLocation = newLoc;
          _currentHeading = p.heading;
          _isConnected = true;
        });

        if (_isFirstLocationUpdate) {
          _mapController.move(newLoc, 17.0);
          _isFirstLocationUpdate = false;
        }

        _checkAreaOutSync();
        _checkSurrenderZoneSync();
      }

      if (_editMode == 'NONE' && !widget.isSelectionMode) {
        await FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('players')
            .doc(_uid)
            .update({
              'location': {'lat': p.latitude, 'lng': p.longitude},
              'heading': p.heading,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _checkAreaOutSync() async {
    if (widget.myRole != 'RUNNER') {
      if (_isOutOfArea) setState(() => _isOutOfArea = false);
      return;
    }

    bool isNowOut = false;
    if (_cachedCurrentAreaPoints.isNotEmpty) {
      List<LatLng> polygon = _cachedCurrentAreaPoints
          .map(
            (p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          )
          .toList();
          
      // 基本エリア内にいるかチェック
      bool isInsideBase = _isPointInPolygon(_myLocation, polygon);

      // 進入禁止エリア内にいるかチェック
      bool isInsideForbidden = false;
      for (var fArea in _cachedForbiddenAreas) {
        if (_isPointInPolygon(_myLocation, fArea)) {
          isInsideForbidden = true;
          break;
        }
      }

      // 「基本エリアの外」 または 「進入禁止エリアの中」 なら警告発動
      isNowOut = !isInsideBase || isInsideForbidden;
    } else {
      isNowOut = false;
    }

    if (isNowOut != _isOutOfArea) {
      setState(() => _isOutOfArea = isNowOut);
    }

    if (_prevOutOfAreaState != isNowOut) {
      _prevOutOfAreaState = isNowOut;
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(_uid)
          .update({'isOutOfArea': isNowOut});
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      int j = (i + 1) % polygon.length;
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  void _checkSurrenderZoneSync() {
    if (!_cachedAllowSurrender) {
      if (_isSurrenderPossible) setState(() => _isSurrenderPossible = false);
      return;
    }
    bool hit = false;
    for (var p in _cachedSurrenderPoints) {
      double dist = Geolocator.distanceBetween(
        _myLocation.latitude,
        _myLocation.longitude,
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      );
      if (dist <= ((p['radius'] as num?)?.toDouble() ?? 20.0)) {
        hit = true;
        break;
      }
    }
    if (hit != _isSurrenderPossible) setState(() => _isSurrenderPossible = hit);
  }

  void _onMapTap(TapPosition t, LatLng p) {
    if (_editMode == 'AREA') {
      setState(() => _tempAreaPoints.add(p));
      return;
    }
    if (_editMode == 'BOX') {
      setState(() {
        _tempBoxMarkers.add(
          Marker(
            point: p,
            width: 40,
            height: 40,
            child: const Icon(
              Icons.check_box_outline_blank,
              color: Colors.purpleAccent,
              size: 40,
            ),
          ),
        );
      });
      return;
    }
    if (_editMode == 'LOCATION') {
      setState(() => _selectedSinglePoint = p);
      return;
    }
    if (widget.myRole == 'GAME MASTER' &&
        _editMode == 'NONE' &&
        !widget.isSelectionMode) {
      _showGMMenu(p);
    }
  }

  void _confirmAreaSelection() {
    if (_tempAreaPoints.length < 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("最低3点必要です")));
      return;
    }
    Navigator.pop(context, _tempAreaPoints);
  }

  void _confirmBoxPlacement() {
    if (_tempBoxMarkers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("BOXを配置してください")));
      return;
    }
    List<LatLng> boxes = _tempBoxMarkers.map((m) => m.point).toList();
    Navigator.pop(context, boxes);
  }

  void _confirmLocationSelection() {
    if (_selectedSinglePoint == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("地点を選択してください")));
      return;
    }
    Navigator.pop(context, _selectedSinglePoint);
  }

  void _showGMMenu(LatLng p) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          color: Colors.grey[900],
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_in_talk, color: Colors.yellow),
                title: const Text("自首P設置", style: TextStyle(color: Colors.white)),
                onTap: () => _addSurrenderPoint(p),
              ),
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("リセット(BOX/自首P)", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  _resetData('surrenderPoints');
                  _resetData('hunterBoxes');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetData(String f) {
    FirebaseFirestore.instance.collection('games').doc('game_001').update({
      f: [],
    });
  }

  void _finishAreaCreation() {
    if (_tempAreaPoints.length < 3) return;
    List<Map<String, double>> pts = _tempAreaPoints
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();
    FirebaseFirestore.instance.collection('games').doc('game_001').update({
      'areaPoints': pts,
    });
    setState(() {
      _editMode = 'NONE';
      _tempAreaPoints = [];
    });
  }

  void _addSurrenderPoint(LatLng p) {
    Navigator.pop(context);
    FirebaseFirestore.instance.collection('games').doc('game_001').update({
      'surrenderPoints': FieldValue.arrayUnion([
        {'lat': p.latitude, 'lng': p.longitude, 'radius': 20.0},
      ]),
    });
  }

  void _lockHunterBox(Map b) async {
    double dist = Geolocator.distanceBetween(
      _myLocation.latitude,
      _myLocation.longitude,
      b['lat'],
      b['lng'],
    );

    if (dist > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("遠すぎます！BOXまであと${(dist - 30).toInt()}m 近づいてください"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("ハンター封印", style: TextStyle(color: Colors.white)),
        content: const Text(
          "このBOXを封印し、ハンター放出を阻止しますか？",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeSealHunterBox(b);
            },
            child: const Text("封印する!"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeSealHunterBox(Map targetBox) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference gameRef = FirebaseFirestore.instance
            .collection('games')
            .doc('game_001');
        DocumentSnapshot snapshot = await transaction.get(gameRef);
        if (!snapshot.exists) return;

        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> boxes = List.from(data['hunterBoxes'] ?? []);

        bool found = false;
        for (var i = 0; i < boxes.length; i++) {
          if ((boxes[i]['id'] != null && boxes[i]['id'] == targetBox['id']) ||
              (boxes[i]['lat'] == targetBox['lat'] &&
                  boxes[i]['lng'] == targetBox['lng'])) {
            if (boxes[i]['isLocked'] == true) throw "既に封印されています";

            boxes[i]['isLocked'] = true;
            boxes[i]['sealedBy'] = widget.myName;
            found = true;
            break;
          }
        }

        if (found) {
          transaction.update(gameRef, {'hunterBoxes': boxes});
          DocumentReference msgRef = FirebaseFirestore.instance
              .collection('games')
              .doc('game_001')
              .collection('messages')
              .doc();
          transaction.set(msgRef, {
            'title': "ハンター阻止！",
            'body': "${widget.myName} がハンター1体を阻止しました！",
            'type': 'SUCCESS',
            'fromName': "SYSTEM",
            'toUid': "ALL",
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("封印完了！通知を送信しました。")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("エラー: $e")));
      }
    }
  }

  void _doSurrender() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("自首しますか？", style: TextStyle(color: Colors.white)),
        content: const Text(
          "現在の賞金を獲得してゲームから離脱します。\nこの操作は取り消せません。",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeSurrender();
            },
            child: const Text("自首する"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeSurrender() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    var gameDoc = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .get();
    var gameData = gameDoc.data()!;

    DateTime startTime = (gameData['startTime'] as Timestamp).toDate();
    DateTime now = DateTime.now();
    double rate = (gameData['settings_moneyRate'] ?? 100).toDouble();

    int elapsed = now.difference(startTime).inSeconds;
    if (elapsed < 0) elapsed = 0;
    int prize = (elapsed * rate).toInt();

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(uid)
        .update({
          'status': 'SURRENDERED',
          'money': prize,
          'isExposed': false,
          'isReported': false,
          'isOutOfArea': false,
          'location': null,
        });

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('messages')
        .add({
          'title': "自首成立",
          'body': "${widget.myName} が自首しました。\n獲得賞金: ¥$prize",
          'type': 'info',
          'toUid': 'ALL',
          'createdAt': FieldValue.serverTimestamp(),
        });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("自首が成立しました")));
      Navigator.pop(context);
    }
  }

  void _catchRunner() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("確保対象を選択"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('games')
                .doc('game_001')
                .collection('players')
                .where('role', isEqualTo: 'RUNNER')
                .where('status', isEqualTo: 'ALIVE')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var p = snapshot.data!.docs[index];
                  var pData = p.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(pData['name']),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);

                        await p.reference.update({
                          'status': 'CAUGHT',
                          'isExposed': false,
                          'isReported': false,
                          'isOutOfArea': false,
                          'location': null,
                        });

                        String title = "確保情報";
                        String body = "${pData['name']} が確保されました";

                        if (pData['isReported'] == true &&
                            pData['reportedBy'] != null) {
                          body =
                              "${pData['reportedBy']} の密告により\n${pData['name']} が確保されました。";
                        }

                        var gameRef = FirebaseFirestore.instance
                            .collection('games')
                            .doc('game_001');
                        var gameSnap = await gameRef.get();
                        var gameData = gameSnap.data() as Map<String, dynamic>;
                        var mission = gameData['activeMission'];

                        if (mission != null &&
                            mission['type'] == 'INFORM' &&
                            mission['hunterRelease'] == true) {
                          int currentCaught = (mission['caughtCount'] ?? 0) + 1;
                          int limit = mission['hunterCount'] ?? 1;

                          await gameRef.update({
                            'activeMission.caughtCount': currentCaught,
                          });

                          body += "\n(密告ミッションによる確保: $currentCaught/$limit 人)";

                          if (currentCaught >= limit) {
                            await gameRef.update({'activeMission': null});
                            await FirebaseFirestore.instance
                                .collection('games')
                                .doc('game_001')
                                .collection('messages')
                                .add({
                                  'title': "ミッション終了",
                                  'body': "規定人数が確保されたため、密告ミッションは終了しました。",
                                  'type': 'SUCCESS',
                                  'toUid': 'ALL',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                          }
                        }

                        await FirebaseFirestore.instance
                            .collection('games')
                            .doc('game_001')
                            .collection('messages')
                            .add({
                              'title': title,
                              'body': body,
                              'type': 'CAUGHT',
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                      },
                      child: const Text("確保"),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isGM = (widget.myRole == 'GAME MASTER');
    bool isHunter = (widget.myRole == 'HUNTER');
    Widget? actionBtn;
    if (isHunter) {
      actionBtn = FloatingActionButton.extended(
        heroTag: "catch",
        backgroundColor: Colors.red,
        label: const Text("確保"),
        onPressed: _catchRunner,
      );
    } else if (!isGM) {
      if (_isOutOfArea) {
        actionBtn = FloatingActionButton.extended(
          heroTag: "alert",
          backgroundColor: Colors.red,
          label: const Text("⚠️ エリア違反"),
          onPressed: null,
        );
      } else if (_isSurrenderPossible)
        actionBtn = FloatingActionButton.extended(
          heroTag: "surrender",
          backgroundColor: Colors.yellowAccent,
          label: const Text("自首する"),
          onPressed: _doSurrender,
        );
    }

    String title = "MAP";
    if (_editMode == 'AREA') title = "範囲をタップで囲む";
    if (_editMode == 'BOX') title = "タップでBOX配置";
    if (_editMode == 'LOCATION') title = "地点をタップ";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.grey[900],
        actions: [
          if (_editMode == 'AREA')
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: _confirmAreaSelection,
            ),
          if (_editMode == 'BOX')
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: _confirmBoxPlacement,
            ),
          if (_editMode == 'LOCATION')
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: _confirmLocationSelection,
            ),
          if (_editMode == 'NONE')
            Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                Icons.circle,
                size: 12,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildMapLayer(isHunter, isGM),
          if (_isOutOfArea && _editMode == 'NONE')
            Container(
              color: Colors.red.withOpacity(0.3),
              child: const Center(
                child: Text(
                  "AREA ALERT\n位置情報が公開されています",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_editMode == 'AREA' && widget.initialMode == 'NORMAL')
            Positioned(
              top: 20,
              child: ElevatedButton(
                onPressed: _finishAreaCreation,
                child: const Text("完了"),
              ),
            ),
          if (_editMode == 'NONE')
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (actionBtn != null) actionBtn,
                    FloatingActionButton(
                      onPressed: () => _mapController.move(_myLocation, 17),
                      child: const Icon(Icons.my_location),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapLayer(bool isHunter, bool isGM) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .snapshots(),
      builder: (context, gameSnap) {
        if (!gameSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var d = gameSnap.data!.data() as Map<String, dynamic>;

        List surrenderPoints = d['surrenderPoints'] ?? [];
        List hunterBoxes = d['hunterBoxes'] ?? [];
        var mission = d['activeMission'];
        bool isBoxMission = mission != null && mission['type'] == 'HUNTER_BOX_MAP';
        bool isVotingMission = mission != null && mission['type'] == 'VOTING';

        List<Polygon> polygons = [];
        List<Marker> markers = [];
        List<CircleMarker> circles = [];

        List<LatLng> displayPolygon = [];
        Map assignments = d['areaAssignments'] ?? {};
        Map splitAreas = d['splitAreas'] ?? {};
        
        Map<String, dynamic> areaSettings = d['areaSettings'] ?? {};
        List defaultArea = areaSettings['playArea'] ?? d['areaPoints'] ?? [];
        List<dynamic> targetPoints = defaultArea;

        String? myAssigned = assignments[_uid];
        if (myAssigned != null && splitAreas.containsKey(myAssigned)) {
          targetPoints = splitAreas[myAssigned];
        }
          
        if (targetPoints.isNotEmpty) {
          displayPolygon = targetPoints
              .map(
                (p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
              )
              .toList();
        }

        // 基本エリア (青)
        if (displayPolygon.isNotEmpty) {
          polygons.add(
            Polygon(
              points: displayPolygon,
              color: Colors.blueAccent.withOpacity(0.1),
              borderColor: Colors.blueAccent,
              borderStrokeWidth: 2,
            ),
          );
        }

        // 進入禁止エリア (赤)
        List<List<LatLng>> currentForbiddenAreas = [];
        if (areaSettings['forbiddenAreas'] != null) {
          for (var areaObj in areaSettings['forbiddenAreas']) {
            // ★修正: Mapから 'points' を取り出す
            var pts = areaObj['points'] as List;
            List<LatLng> fPoints = pts.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
            currentForbiddenAreas.add(fPoints);
            polygons.add(
              Polygon(
                points: fPoints,
                color: Colors.red.withOpacity(0.3),
                borderColor: Colors.redAccent,
                borderStrokeWidth: 2,
              )
            );
          }
        }

        // 2. 投票ミッション用エリア
        if (isVotingMission) {
          List<dynamic> rawA = mission['areaPointsA'] ?? [];
          List<dynamic> rawB = mission['areaPointsB'] ?? [];

          if (rawA.isNotEmpty) {
            List<LatLng> pointsA = rawA
                .map(
                  (p) => LatLng(
                    (p['lat'] as num).toDouble(),
                    (p['lng'] as num).toDouble(),
                  ),
                )
                .toList();
            polygons.add(
              Polygon(
                points: pointsA,
                color: Colors.red.withOpacity(0.3),
                borderColor: Colors.redAccent,
                borderStrokeWidth: 2,
                label: "エリアA",
              ),
            );
          }
          if (rawB.isNotEmpty) {
            List<LatLng> pointsB = rawB
                .map(
                  (p) => LatLng(
                    (p['lat'] as num).toDouble(),
                    (p['lng'] as num).toDouble(),
                  ),
                )
                .toList();
            polygons.add(
              Polygon(
                points: pointsB,
                color: Colors.blue[900]!.withOpacity(0.4),
                borderColor: Colors.blue[900]!,
                borderStrokeWidth: 2,
                label: "エリアB",
              ),
            );
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _cachedCurrentAreaPoints = targetPoints;
            _cachedForbiddenAreas = currentForbiddenAreas; 
            _cachedSurrenderPoints = surrenderPoints;
            _cachedAllowSurrender = d['settings_allowSurrender'] ?? true;
            _checkAreaOutSync();
          }
        });

        // 3. その他マーカー
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('games')
              .doc('game_001')
              .collection('players')
              .snapshots(),
          builder: (context, playerSnap) {
            if (_tempAreaPoints.isNotEmpty && _editMode == 'AREA') {
              polygons.add(
                Polygon(
                  points: _tempAreaPoints,
                  color: Colors.yellowAccent.withOpacity(0.2),
                  borderColor: Colors.yellow,
                  borderStrokeWidth: 2,
                ),
              );
              for (var p in _tempAreaPoints) {
                markers.add(
                  Marker(
                    point: p,
                    width: 20,
                    height: 20,
                    child: const Icon(
                      Icons.circle,
                      color: Colors.yellow,
                      size: 10,
                    ),
                  ),
                );
              }
            }
            if (_editMode == 'BOX') markers.addAll(_tempBoxMarkers);
            if (_editMode == 'LOCATION' && _selectedSinglePoint != null) {
              markers.add(
                Marker(
                  point: _selectedSinglePoint!,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.greenAccent,
                    size: 40,
                  ),
                ),
              );
            }

           
            // ハンターBOX
            for (var b in hunterBoxes) {
              bool locked = b['isLocked'] ?? false;
              markers.add(
                Marker(
                  point: LatLng(b['lat'], b['lng']),
                  width: 60, // ★少しだけタップ判定を広げました
                  height: 60,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque, // ★追加: 透明な部分をタップしても反応するようにする
                    onTap: () {
                      // ★追加: なぜ反応しないのか原因を画面に出すように変更
                      if (locked) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("このBOXは既に封印されています")));
                        return;
                      }
                      if (widget.myRole != 'RUNNER') {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("BOXを封印できるのは「逃走者」のみです", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                        return;
                      }
                      if (!isBoxMission) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("現在、ハンターBOXミッションは発動していません", style: TextStyle(color: Colors.white)), backgroundColor: Colors.orange));
                        return;
                      }
                      
                      // すべての条件をクリアしたら封印処理へ
                      _lockHunterBox(b);
                    },
                    child: Column(
                      children: [
                        Icon(
                          locked ? Icons.lock : Icons.check_box_outline_blank,
                          color: locked ? Colors.green : Colors.red,
                          size: 30,
                        ),
                        Text(
                          locked ? "LOCKED" : "UNLOCK",
                          style: TextStyle(
                            fontSize: 8,
                            color: locked ? Colors.green : Colors.red,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // 自首ポイント
            for (var p in surrenderPoints) {
              circles.add(
                CircleMarker(
                  point: LatLng(p['lat'], p['lng']),
                  radius: 20,
                  color: Colors.yellowAccent.withOpacity(0.2),
                  borderColor: Colors.yellow,
                  borderStrokeWidth: 2,
                  useRadiusInMeter: true,
                ),
              );
              markers.add(
                Marker(
                  point: LatLng(p['lat'], p['lng']),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.phone_in_talk,
                    color: Colors.blueAccent,
                  ),
                ),
              );
            }

            // プレイヤー位置表示
            if (playerSnap.hasData && _editMode == 'NONE') {
              for (var doc in playerSnap.data!.docs) {
                var pd = doc.data() as Map<String, dynamic>;

                if ((isHunter || isGM) &&
                    pd['isReported'] == true &&
                    pd['reportLocation'] != null &&
                    pd['role'] == 'RUNNER' &&
                    pd['status'] == 'ALIVE') {
                  var rLoc = pd['reportLocation'];
                  double? rLat = (rLoc['lat'] as num?)?.toDouble();
                  double? rLng = (rLoc['lng'] as num?)?.toDouble();

                  if (rLat != null && rLng != null) {
                    markers.add(
                      Marker(
                        point: LatLng(rLat, rLng),
                        width: 80,
                        height: 80,
                        child: Column(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: Colors.red,
                              size: 40,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "密告: ${pd['name']}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }

                if (pd['location'] == null) continue;
                double? pLat = (pd['location']['lat'] as num?)?.toDouble();
                double? pLng = (pd['location']['lng'] as num?)?.toDouble();
                if (pLat == null || pLng == null) continue;

                bool isMe = (doc.id == _uid);
                bool isExposed = pd['isExposed'] ?? false;
                bool isOutOfArea = pd['isOutOfArea'] ?? false;
                bool isCaught = pd['status'] == 'CAUGHT';
                bool isSurrendered = pd['status'] == 'SURRENDERED';

                if (isCaught || isSurrendered) continue;

                bool visible = false;
                if (isMe || isGM) {
                  visible = true;
                } else if (pd['role'] == 'HUNTER' && isHunter)
                  visible = true;
                else if (isHunter && (isExposed || isOutOfArea))
                  visible = true;

                if (!visible) continue;

                Color iconColor = Colors.blue;
                if (pd['role'] == 'HUNTER') {
                  iconColor = Colors.red;
                }

                markers.add(
                  Marker(
                    point: LatLng(pLat, pLng),
                    width: 120,
                    height: 120,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pd['name'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Transform.rotate(
                          angle:
                              (((pd['heading'] as num?)?.toDouble() ?? 0.0) *
                              (math.pi / 180)),
                          child: Icon(
                            Icons.navigation,
                            color: iconColor,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _myLocation,
                initialZoom: 17,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.run_for_money',
                ),
                CircleLayer(circles: circles),
                PolygonLayer(polygons: polygons),
                MarkerLayer(markers: markers),
              ],
            );
          },
        );
      },
    );
  }
}