import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';

class MissionControlScreen extends StatefulWidget {
  const MissionControlScreen({super.key});
  @override
  State<MissionControlScreen> createState() => _MissionControlScreenState();
}

class _MissionControlScreenState extends State<MissionControlScreen> {
  // エリア選択投票用の一時変数
  List<LatLng>? _selectedAreaA;
  List<LatLng>? _selectedAreaB;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 汎用ペナルティ設定ウィジェット
  Widget _buildPenaltySelector({
    required String selectedType,
    required int hunterCount,
    required Function(String) onTypeChanged,
    required Function(String) onCountChanged,
    bool excludeLocationExpose = false, // 密告ミッション用に位置公開を除外するフラグ
  }) {
    // 選択肢の作成
    List<DropdownMenuItem<String>> items = [
      const DropdownMenuItem(value: 'NONE', child: Text("なし")),
      const DropdownMenuItem(value: 'HUNTER_RELEASE', child: Text("ハンター放出")),
    ];

    if (!excludeLocationExpose) {
      items.add(
        const DropdownMenuItem(value: 'LOCATION_EXPOSE', child: Text("位置情報公開")),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.grey, height: 30),
        const Text(
          "失敗時ペナルティ設定",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: selectedType,
          dropdownColor: Colors.grey[800],
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.redAccent),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
          items: items,
          onChanged: (val) => onTypeChanged(val!),
        ),
        if (selectedType == 'HUNTER_RELEASE')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: hunterCount.toString()),
              onChanged: onCountChanged,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "放出体数",
                labelStyle: TextStyle(color: Colors.redAccent),
                prefixIcon: Icon(Icons.person_add, color: Colors.redAccent),
              ),
            ),
          ),
      ],
    );
  }

  // ====================================================
  // 1. 暗号解読ミッション (修正版)
  // ====================================================
  Future<void> _startCodeMission() async {
    bool isLocationRestricted = false;
    LatLng? inputLocation;

    String penaltyType = 'NONE';
    int penaltyHunterCount = 1;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final TextEditingController timeCtrl = TextEditingController(
              text: "10",
            );
            final TextEditingController descCtrl = TextEditingController(
              text: "",
            );

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                "暗号解読設定",
                style: TextStyle(color: Colors.indigoAccent),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "制限時間 (分)",
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "※指令文はペナルティ設定に基づいて自動生成されます",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),

                    const Divider(color: Colors.grey, height: 30),
                    SwitchListTile(
                      title: const Text(
                        "入力場所を制限する",
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        "特定の場所でのみ入力可能にする",
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      activeThumbColor: Colors.indigoAccent,
                      value: isLocationRestricted,
                      onChanged: (val) {
                        setState(() {
                          isLocationRestricted = val;
                          if (!val) inputLocation = null;
                        });
                      },
                    ),
                    if (isLocationRestricted)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: inputLocation == null
                              ? Colors.grey
                              : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.map),
                        label: Text(
                          inputLocation == null ? "入力場所を指定" : "場所設定済み",
                        ),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MapScreen(
                                myRole: 'GAME MASTER',
                                myName: 'GM',
                                initialMode: 'SELECT_LOCATION',
                              ),
                            ),
                          );
                          if (result != null && result is LatLng) {
                            setState(() => inputLocation = result);
                          }
                        },
                      ),

                    _buildPenaltySelector(
                      selectedType: penaltyType,
                      hunterCount: penaltyHunterCount,
                      onTypeChanged: (val) => setState(() => penaltyType = val),
                      onCountChanged: (val) =>
                          penaltyHunterCount = int.tryParse(val) ?? 1,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("キャンセル"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigoAccent,
                  ),
                  onPressed: () async {
                    if (isLocationRestricted && inputLocation == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("入力場所を指定してください")),
                      );
                      return;
                    }

                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    var snapshot = await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('players')
                        .where('role', isEqualTo: 'RUNNER')
                        .where('status', isEqualTo: 'ALIVE')
                        .get();
                    if (snapshot.docs.isEmpty) {
                      _notify("生存中の逃走者がいません");
                      return;
                    }

                    String code = (1000 + Random().nextInt(9000)).toString();
                    List<String> digits = code.split('');
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    // ★修正: 指令文の自動生成 (例外条件の追加)
                    String bodyText = "";
                    if (penaltyType == 'HUNTER_RELEASE') {
                      bodyText =
                          "残り$min分で、ハンター$penaltyHunterCount体がエリアに追加される。\nこの事態を回避するには、\nメールで送られたコードの断片を逃走者同士で共有し、\n正しいコードを入力せよ。";
                    } else if (penaltyType == 'LOCATION_EXPOSE') {
                      // ★ここを変更: 正しいコードを入力した者は通達されない旨を明記
                      bodyText =
                          "残り$min分で、逃走者全員の位置情報がハンターに通達される。\n(ただし、正しいコードを入力した者は通達されない。)\nこの事態を回避するには、\nメールで送られたコードの断片を逃走者同士で共有し、\n正しいコードを入力せよ。";
                    } else {
                      bodyText = "制限時間内に暗号を解読し、コードを入力せよ。\n残り$min分でミッションは終了する。";
                    }

                    if (isLocationRestricted) {
                      bodyText += "\n\n【注意】\nコードの入力は「指定された地点（端末）」でしか行えない。";
                    } else {
                      bodyText += "\n\n(コードが分かったらその場で入力せよ)";
                    }

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({
                          'activeMission': {
                            'type': 'CODE',
                            'title': "暗号を解読せよ",
                            'description': bodyText,
                            'correctCode': code,
                            'endTime': Timestamp.fromDate(end),
                            'isLocationRestricted': isLocationRestricted,
                            'inputLocation': isLocationRestricted
                                ? {
                                    'lat': inputLocation!.latitude,
                                    'lng': inputLocation!.longitude,
                                  }
                                : null,
                            'clearedUids': [],
                            'penaltyType': penaltyType,
                            'penaltyHunterCount': penaltyHunterCount,
                          },
                        });

                    // ヒント配布
                    List<QueryDocumentSnapshot> runners = snapshot.docs;
                    int count = runners.length;
                    for (int i = 0; i < count; i++) {
                      String hint = "";
                      if (count == 1) {
                        hint = "コードは「$code」";
                      } else if (count == 2)
                        hint = (i == 0)
                            ? "1,2文字目: ${digits[0]}${digits[1]}"
                            : "3,4文字目: ${digits[2]}${digits[3]}";
                      else if (count == 3)
                        hint = (i == 0)
                            ? "1,2文字目: ${digits[0]}${digits[1]}"
                            : (i == 1
                                  ? "3文字目: ${digits[2]}"
                                  : "4文字目: ${digits[3]}");
                      else
                        hint = "${(i % 4) + 1}文字目: ${digits[i % 4]}";

                      await FirebaseFirestore.instance
                          .collection('games')
                          .doc('game_001')
                          .collection('messages')
                          .add({
                            'title': "極秘コード断片",
                            'body': hint,
                            'type': 'MISSION_HINT',
                            'toUid': runners[i].id,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                    }

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': "MISSION発動！",
                          'body': bodyText,
                          'type': 'MISSION',
                          'toUid': 'ALL',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                    if (mounted) {
                      Navigator.pop(context);
                      _notify("暗号ミッションを開始しました");
                    }
                  },
                  child: const Text("開始"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ====================================================
  // 2. エリア選択投票ミッション
  // ====================================================
  Future<void> _startVotingMission() async {
    String penaltyType = 'NONE';
    int penaltyHunterCount = 1;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final TextEditingController timeCtrl = TextEditingController(
              text: "10",
            );

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                "エリア投票設定",
                style: TextStyle(color: Colors.orangeAccent),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "制限時間 (分)",
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "エリアAとBを地図で指定してください",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.map),
                      label: Text(
                        _selectedAreaA == null ? "エリアAを指定" : "エリアA (設定済)",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedAreaA == null
                            ? Colors.grey
                            : Colors.green,
                      ),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MapScreen(
                              myRole: 'GAME MASTER',
                              myName: 'GM',
                              initialMode: 'SELECT_AREA',
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() => _selectedAreaA = result);
                        }
                      },
                    ),
                    const SizedBox(height: 5),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.map),
                      label: Text(
                        _selectedAreaB == null ? "エリアBを指定" : "エリアB (設定済)",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedAreaB == null
                            ? Colors.grey
                            : Colors.green,
                      ),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MapScreen(
                              myRole: 'GAME MASTER',
                              myName: 'GM',
                              initialMode: 'SELECT_AREA',
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() => _selectedAreaB = result);
                        }
                      },
                    ),

                    _buildPenaltySelector(
                      selectedType: penaltyType,
                      hunterCount: penaltyHunterCount,
                      onTypeChanged: (val) => setState(() => penaltyType = val),
                      onCountChanged: (val) =>
                          penaltyHunterCount = int.tryParse(val) ?? 1,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("キャンセル"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                  ),
                  onPressed: () async {
                    if (_selectedAreaA == null || _selectedAreaB == null) {
                      _notify("エリアAとBの両方を指定してください");
                      return;
                    }

                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    String bodyText = "";
                    if (penaltyType == 'HUNTER_RELEASE') {
                      bodyText =
                          "逃走エリアが2つに分割される。\nこれから行われる投票によって、\n票数の少ないエリアには、\nハンター$penaltyHunterCount体が放出される。";
                    } else if (penaltyType == 'LOCATION_EXPOSE') {
                      bodyText =
                          "逃走エリアが2つに分割される。\nこれから行われる投票によって、\n票数の少ないエリアにいる逃走者の位置情報が、\nハンターに通達される。";
                    } else {
                      bodyText = "逃走エリアが2つに分割される。\nどちらかのエリアに投票せよ。";
                    }

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({
                          'activeMission': {
                            'type': 'VOTING',
                            'title': "エリアを選択せよ",
                            'description': bodyText,
                            'candidates': {'A': 'エリアA', 'B': 'エリアB'},
                            'votes': {},
                            'endTime': Timestamp.fromDate(end),
                            'areaPointsA': _selectedAreaA!
                                .map(
                                  (p) => {
                                    'lat': p.latitude,
                                    'lng': p.longitude,
                                  },
                                )
                                .toList(),
                            'areaPointsB': _selectedAreaB!
                                .map(
                                  (p) => {
                                    'lat': p.latitude,
                                    'lng': p.longitude,
                                  },
                                )
                                .toList(),
                            'penaltyType': penaltyType,
                            'penaltyHunterCount': penaltyHunterCount,
                          },
                        });

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': "MISSION発動！",
                          'body': bodyText,
                          'type': 'MISSION',
                          'toUid': 'ALL',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                    if (mounted) {
                      Navigator.pop(context);
                      _notify("投票ミッションを開始しました");
                      setState(() {
                        _selectedAreaA = null;
                        _selectedAreaB = null;
                      });
                    }
                  },
                  child: const Text("開始"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ====================================================
  // 3. ハンターBOX封印ミッション
  // ====================================================
  Future<void> _startHunterBoxMission() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final TextEditingController timeCtrl = TextEditingController(
              text: "10",
            );

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                "ハンターBOX設定",
                style: TextStyle(color: Colors.purpleAccent),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: timeCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "制限時間 (分)",
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text("地図でBOXを配置する"),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MapScreen(
                            myRole: 'GAME MASTER',
                            myName: 'GM',
                            initialMode: 'PLACE_BOX',
                          ),
                        ),
                      );
                      if (result != null && result is List<LatLng>) {
                        List<Map<String, dynamic>> boxes = result
                            .map(
                              (p) => {
                                'lat': p.latitude,
                                'lng': p.longitude,
                                'isLocked': false,
                              },
                            )
                            .toList();
                        await FirebaseFirestore.instance
                            .collection('games')
                            .doc('game_001')
                            .update({'hunterBoxes': boxes});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("${boxes.length}個のBOXを設置しました"),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("キャンセル"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                  ),
                  onPressed: () async {
                    var doc = await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .get();
                    List boxes = doc.data()?['hunterBoxes'] ?? [];
                    if (boxes.isEmpty) {
                      _notify("BOXが設置されていません");
                      return;
                    }

                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    String bodyText =
                        "エリア内${boxes.length}ヶ所に設置されたハンターBOXが解除され、\n中からハンターが放出される。\nハンター放出を阻止するには、\nハンターBOXの近くまで行き、地図を使って封印せよ。\n制限時間は$min分。\n時間内に封印できなければ、\nエリアにハンターが解き放たれることとなる。";

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({
                          'activeMission': {
                            'type': 'HUNTER_BOX_MAP',
                            'title': "ハンター放出を阻止せよ",
                            'description': bodyText,
                            'endTime': Timestamp.fromDate(end),
                          },
                        });
                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': "MISSION発動！",
                          'body': bodyText,
                          'type': 'MISSION',
                          'toUid': 'ALL',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                    if (mounted) {
                      Navigator.pop(context);
                      _notify("ハンターBOXミッションを開始しました");
                    }
                  },
                  child: const Text("開始"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ====================================================
  // 4. 復活ミッション
  // ====================================================
  Future<void> _startRevivalMission() async {
    final TextEditingController countCtrl = TextEditingController(text: "3");
    final TextEditingController timeCtrl = TextEditingController(text: "10");
    final TextEditingController groupCtrl = TextEditingController(text: "2");

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "復活ミッション設定",
          style: TextStyle(color: Colors.greenAccent),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: timeCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "制限時間 (分)",
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "復活可能人数 (最大発行枚数)",
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: groupCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "撮影に必要な人数 (〇人組)",
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              int min = int.tryParse(timeCtrl.text) ?? 10;
              int limit = int.tryParse(countCtrl.text) ?? 3;
              String groupSize = groupCtrl.text;

              DateTime now = DateTime.now();
              DateTime end = now.add(Duration(minutes: min));

              String bodyText =
                  "牢獄に捕らわれた逃走者を復活させるチャンスだ。残り$min分までに、$groupSize人組で写真を撮影し、GMに送信せよ。条件をクリアするごとに、復活カードを1枚獲得できる。ただし、1人の逃走者につき獲得できる復活カードは1枚まで、さらに、発行できる復活カードは最大$limit枚までとなっている。制限時間内に仲間を救い出せるかは、君たちの行動次第だ。";

              await FirebaseFirestore.instance
                  .collection('games')
                  .doc('game_001')
                  .update({
                    'activeMission': {
                      'type': 'REVIVAL',
                      'title': "牢獄から救出せよ",
                      'description': bodyText,
                      'endTime': Timestamp.fromDate(end),
                      'qrLimit': limit,
                      'qrIssuedCount': 0,
                    },
                  });
              await FirebaseFirestore.instance
                  .collection('games')
                  .doc('game_001')
                  .collection('messages')
                  .add({
                    'title': "MISSION発動！",
                    'body': bodyText,
                    'type': 'MISSION',
                    'toUid': 'ALL',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

              if (mounted) {
                Navigator.pop(context);
                _notify("復活ミッションを開始しました");
              }
            },
            child: const Text("開始"),
          ),
        ],
      ),
    );
  }

  // ====================================================
  // 5. 密告ミッション (微調整版 - 位置公開なし)
  // ====================================================
  Future<void> _startInformerMission() async {
    String penaltyType = 'HUNTER_RELEASE';
    int penaltyHunterCount = 1;
    bool enableEndCondition = true;
    int endConditionCount = 1;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final TextEditingController timeCtrl = TextEditingController(
              text: "10",
            );

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                "密告ミッション設定",
                style: TextStyle(color: Colors.redAccent),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "制限時間 (分)",
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.timer, color: Colors.white),
                      ),
                    ),
                    const Divider(color: Colors.grey, height: 30),

                    SwitchListTile(
                      title: const Text(
                        "規定人数確保で終了",
                        style: TextStyle(color: Colors.white),
                      ),
                      activeThumbColor: Colors.orange,
                      value: enableEndCondition,
                      onChanged: (val) =>
                          setState(() => enableEndCondition = val),
                    ),
                    if (enableEndCondition)
                      TextField(
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                          text: endConditionCount.toString(),
                        ),
                        onChanged: (val) =>
                            endConditionCount = int.tryParse(val) ?? 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "終了条件 (確保人数)",
                          labelStyle: TextStyle(color: Colors.orange),
                        ),
                      ),

                    _buildPenaltySelector(
                      selectedType: penaltyType,
                      hunterCount: penaltyHunterCount,
                      onTypeChanged: (val) => setState(() => penaltyType = val),
                      onCountChanged: (val) =>
                          penaltyHunterCount = int.tryParse(val) ?? 1,
                      excludeLocationExpose: true, // 位置公開を除外
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("キャンセル"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: () async {
                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    String bodyText = "";
                    if (penaltyType == 'HUNTER_RELEASE') {
                      bodyText =
                          "残り$min分で、ハンター$penaltyHunterCount体がエリアに放出される。\nこれを阻止する方法はただ一つ。\n他の逃走者の位置を密告し、自分の身を守れ。\n密告によって逃走者が$endConditionCount人確保されるごとに、\nハンターの放出を1体分阻止することができる。";
                    } else {
                      bodyText = "裏切り者が現れた。他逃走者の位置を密告せよ。\n制限時間は$min分だ。";
                    }

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({
                          'activeMission': {
                            'type': 'INFORM',
                            'title': "密告せよ！",
                            'description': bodyText,
                            'endTime': Timestamp.fromDate(end),
                            'hunterRelease': enableEndCondition,
                            'hunterCount': endConditionCount,
                            'caughtCount': 0,
                            'penaltyType': penaltyType,
                            'penaltyHunterCount': penaltyHunterCount,
                          },
                        });

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': "MISSION発動！",
                          'body': bodyText,
                          'type': 'MISSION',
                          'toUid': 'ALL',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                    if (mounted) {
                      Navigator.pop(context);
                      _notify("密告ミッションを開始しました");
                    }
                  },
                  child: const Text("開始"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ====================================================
  // 共通処理
  // ====================================================
  Future<void> _stopMission() async {
    await FirebaseFirestore.instance.collection('games').doc('game_001').update(
      {'activeMission': null, 'hunterBoxes': []},
    );
    var p = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .get();
    for (var d in p.docs) {
      if (d['isExposed'] == true || d['isReported'] == true) {
        d.reference.update({
          'isExposed': false,
          'isReported': false,
          'reportedBy': null,
          'reportLocation': null,
        });
      }
    }
    _notify("ミッション終了");
  }

  Widget _buildBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color,
          alignment: Alignment.centerLeft,
          side: BorderSide(color: color),
        ),
        icon: Icon(icon, size: 30),
        label: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "MISSION CONTROL",
          style: TextStyle(fontFamily: 'Courier'),
        ),
        backgroundColor: Colors.grey[900],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .snapshots(),
        builder: (context, snapshot) {
          bool active = false;
          String missionTitle = "";
          if (snapshot.hasData && snapshot.data!.exists) {
            var data = snapshot.data!.data() as Map<String, dynamic>;
            if (data['activeMission'] != null) {
              active = true;
              missionTitle = data['activeMission']['title'] ?? "進行中";
            }
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  border: Border.all(
                    color: active ? Colors.redAccent : Colors.greenAccent,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      active ? "MISSION ACTIVE" : "NO MISSION",
                      style: TextStyle(
                        color: active ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                      ),
                    ),
                    if (active)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          missionTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    !active
                        ? const Text(
                            "ミッションを選択してください",
                            style: TextStyle(color: Colors.grey),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: _stopMission,
                            child: const Text("強制終了"),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildBtn(
                Icons.dialpad,
                "暗号解読",
                Colors.indigo,
                active ? null : _startCodeMission,
              ),
              const SizedBox(height: 10),
              _buildBtn(
                Icons.thumbs_up_down,
                "エリア選択投票 (地図指定)",
                Colors.orange,
                active ? null : _startVotingMission,
              ),
              const SizedBox(height: 10),
              _buildBtn(
                Icons.lock,
                "ハンターBOX (地図配置)",
                Colors.purple,
                active ? null : _startHunterBoxMission,
              ),
              const SizedBox(height: 10),
              _buildBtn(
                Icons.camera_alt,
                "復活 (写真)",
                Colors.green,
                active ? null : _startRevivalMission,
              ),
              const SizedBox(height: 10),
              _buildBtn(
                Icons.warning,
                "密告 (位置送信)",
                Colors.red,
                active ? null : _startInformerMission,
              ),
            ],
          );
        },
      ),
    );
  }
}

