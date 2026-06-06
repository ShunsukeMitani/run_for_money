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
      const DropdownMenuItem(value: 'HUNTER_RELEASE', child: Text("チェイサー放出")),
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
  // 1. 暗号解読ミッション
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
            final TextEditingController timeCtrl = TextEditingController(text: "10");
            final TextEditingController descCtrl = TextEditingController(text: "");
            final TextEditingController bonusCtrl = TextEditingController(text: "100"); // ★追加：ボーナス額入力

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("暗号解読設定", style: TextStyle(color: Colors.indigoAccent)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: "制限時間 (分)", labelStyle: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 10),
                    const Text("※指令文は設定に基づいて自動生成されます", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const Divider(color: Colors.grey, height: 30),
                    
                    // ★追加：成功ボーナス設定
                    const Text("成功時ボーナス設定", style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: bonusCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "単価アップ額 (円/秒)",
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.trending_up, color: Colors.yellowAccent),
                      ),
                    ),

                    const Divider(color: Colors.grey, height: 30),
                    SwitchListTile(
                      title: const Text("入力場所を制限する", style: TextStyle(color: Colors.white)),
                      subtitle: const Text("特定の場所でのみ入力可能にする", style: TextStyle(color: Colors.grey, fontSize: 10)),
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
                        style: ElevatedButton.styleFrom(backgroundColor: inputLocation == null ? Colors.grey : Colors.green, foregroundColor: Colors.white),
                        icon: const Icon(Icons.map),
                        label: Text(inputLocation == null ? "入力場所を指定" : "場所設定済み"),
                        onPressed: () async {
                          final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const MapScreen(myRole: 'GAME MASTER', myName: 'GM', initialMode: 'SELECT_LOCATION')));
                          if (result != null && result is LatLng) setState(() => inputLocation = result);
                        },
                      ),

                    _buildPenaltySelector(
                      selectedType: penaltyType,
                      hunterCount: penaltyHunterCount,
                      onTypeChanged: (val) => setState(() => penaltyType = val),
                      onCountChanged: (val) => penaltyHunterCount = int.tryParse(val) ?? 1,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
                  onPressed: () async {
                    if (isLocationRestricted && inputLocation == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("入力場所を指定してください")));
                      return;
                    }

                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    var snapshot = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').where('role', isEqualTo: 'RUNNER').where('status', isEqualTo: 'ALIVE').get();
                    if (snapshot.docs.isEmpty) {
                      _notify("生存中のサバイバーがいません");
                      return;
                    }

                    String code = (1000 + Random().nextInt(9000)).toString();
                    List<String> digits = code.split('');
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    String bodyText = "";
                    if (penaltyType == 'HUNTER_RELEASE') {
                      bodyText = "残り$min分で、チェイサー$penaltyHunterCount体が追加される。\n(正しいコードを入力した者は通達されない。)\nこの事態を回避するには、メールの断片を共有し正しいコードを入力せよ。";
                    } else if (penaltyType == 'LOCATION_EXPOSE') {
                      bodyText = "残り$min分で、サバイバー全員の位置情報がチェイサーに通達される。\n(正しいコードを入力した者は通達されない。)\nこの事態を回避するには、メールの断片を共有し正しいコードを入力せよ。";
                    } else {
                      bodyText = "制限時間内に暗号を解読し、コードを入力せよ。\n残り$min分でミッションは終了する。";
                    }

                    if (isLocationRestricted) {
                      bodyText += "\n\n【注意】\nコード入力は「指定された地点」でしか行えない。";
                    } else {
                      bodyText += "\n\n(コードが分かったらその場で入力せよ)";
                    }

                    await FirebaseFirestore.instance.collection('games').doc('game_001').update({
                      'activeMission': {
                        'type': 'CODE',
                        'title': "暗号を解読せよ",
                        'description': bodyText,
                        'correctCode': code,
                        'endTime': Timestamp.fromDate(end),
                        'isLocationRestricted': isLocationRestricted,
                        'inputLocation': isLocationRestricted ? {'lat': inputLocation!.latitude, 'lng': inputLocation!.longitude} : null,
                        'clearedUids': [],
                        'penaltyType': penaltyType,
                        'penaltyHunterCount': penaltyHunterCount,
                        'bonusRate': int.tryParse(bonusCtrl.text) ?? 100, // ★ボーナス設定を保存！
                      },
                    });

                    List<QueryDocumentSnapshot> runners = snapshot.docs;
                    int count = runners.length;
                    for (int i = 0; i < count; i++) {
                      String hint = "";
                      if (count == 1) hint = "コードは「$code」";
                      else if (count == 2) hint = (i == 0) ? "1,2文字目: ${digits[0]}${digits[1]}" : "3,4文字目: ${digits[2]}${digits[3]}";
                      else if (count == 3) hint = (i == 0) ? "1,2文字目: ${digits[0]}${digits[1]}" : (i == 1 ? "3文字目: ${digits[2]}" : "4文字目: ${digits[3]}");
                      else hint = "${(i % 4) + 1}文字目: ${digits[i % 4]}";

                      await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                        'title': "極秘コード断片", 'body': hint, 'type': 'MISSION_HINT', 'toUid': runners[i].id, 'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                      'title': "MISSION発動！", 'body': bodyText, 'type': 'MISSION', 'toUid': 'ALL', 'createdAt': FieldValue.serverTimestamp(),
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
                          "逃走エリアが2つに分割される。\nこれから行われる投票によって、\n票数の少ないエリアには、\nチェイサー$penaltyHunterCount体が放出される。";
                    } else if (penaltyType == 'LOCATION_EXPOSE') {
                      bodyText =
                          "逃走エリアが2つに分割される。\nこれから行われる投票によって、\n票数の少ないエリアにいるサバイバーの位置情報が、\nチェイサーに通達される。";
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
  // 3. チェイサーBOX封印ミッション
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
                "チェイサーBOX設定",
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
                        "エリア内${boxes.length}ヶ所に設置されたチェイサーBOXが解除され、\n中からチェイサーが放出される。\nチェイサー放出を阻止するには、\nチェイサーBOXの近くまで行き、地図を使って封印せよ。\n制限時間は$min分。\n時間内に封印できなければ、\nエリアにチェイサーが解き放たれることとなる。";

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({
                          'activeMission': {
                            'type': 'HUNTER_BOX_MAP',
                            'title': "チェイサー放出を阻止せよ",
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
                      _notify("チェイサーBOXミッションを開始しました");
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
                  "牢獄に捕らわれたサバイバーを復活させるチャンスだ。残り$min分までに、$groupSize人組で写真を撮影し、GMに送信せよ。条件をクリアするごとに、復活カードを1枚獲得できる。ただし、1人のサバイバーにつき獲得できる復活カードは1枚まで、さらに、発行できる復活カードは最大$limit枚までとなっている。制限時間内に仲間を救い出せるかは、君たちの行動次第だ。";

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
  // 5. 密告ミッション
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
            final TextEditingController timeCtrl = TextEditingController(text: "10");
            final TextEditingController bonusCtrl = TextEditingController(text: "100"); // ★追加：ボーナス額入力

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("密告ミッション設定", style: TextStyle(color: Colors.redAccent)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: "制限時間 (分)", labelStyle: TextStyle(color: Colors.grey), prefixIcon: Icon(Icons.timer, color: Colors.white)),
                    ),
                    const Divider(color: Colors.grey, height: 30),

                    // ★追加：成功ボーナス設定
                    const Text("成功時ボーナス設定", style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: bonusCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "単価アップ額 (円/秒)",
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.trending_up, color: Colors.yellowAccent),
                      ),
                    ),
                    const Divider(color: Colors.grey, height: 30),

                    SwitchListTile(
                      title: const Text("規定人数確保で終了", style: TextStyle(color: Colors.white)),
                      activeThumbColor: Colors.orange,
                      value: enableEndCondition,
                      onChanged: (val) => setState(() => enableEndCondition = val),
                    ),
                    if (enableEndCondition)
                      TextField(
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: endConditionCount.toString()),
                        onChanged: (val) => endConditionCount = int.tryParse(val) ?? 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: "終了条件 (確保人数)", labelStyle: TextStyle(color: Colors.orange)),
                      ),

                    _buildPenaltySelector(
                      selectedType: penaltyType,
                      hunterCount: penaltyHunterCount,
                      onTypeChanged: (val) => setState(() => penaltyType = val),
                      onCountChanged: (val) => penaltyHunterCount = int.tryParse(val) ?? 1,
                      excludeLocationExpose: true, 
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    int min = int.tryParse(timeCtrl.text) ?? 10;
                    DateTime now = DateTime.now();
                    DateTime end = now.add(Duration(minutes: min));

                    String bodyText = "";
                    if (penaltyType == 'HUNTER_RELEASE') {
                      bodyText = "残り$min分で、チェイサー$penaltyHunterCount体がエリアに放出される。\nこれを阻止する方法はただ一つ。\n他のサバイバーの位置を密告し、自分の身を守れ。\n密告によってサバイバーが$endConditionCount人確保されるごとに、\nチェイサーの放出を1体分阻止することができる。";
                    } else {
                      bodyText = "裏切り者が現れた。他サバイバーの位置を密告せよ。\n制限時間は$min分だ。";
                    }

                    await FirebaseFirestore.instance.collection('games').doc('game_001').update({
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
                        'bonusRate': int.tryParse(bonusCtrl.text) ?? 100, // ★ボーナス設定を保存！
                      },
                    });

                    await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                      'title': "MISSION発動！", 'body': bodyText, 'type': 'MISSION', 'toUid': 'ALL', 'createdAt': FieldValue.serverTimestamp(),
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
  // 共通処理（ミッション強制終了 ＆ 投票集計）
  // ====================================================
  Future<void> _stopMission() async {
    var gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
    var gameSnap = await gameRef.get();
    
    if (gameSnap.exists) {
      var gameData = gameSnap.data() as Map<String, dynamic>;
      var mission = gameData['activeMission'];

      // ★ここから追加：もし終わったミッションが「エリア投票」だった場合の特別処理
      if (mission != null && mission['type'] == 'VOTING') {
        // ① 投票の集計
        Map votes = mission['votes'] ?? {};
        int countA = 0;
        int countB = 0;
        votes.forEach((uid, vote) {
          if (vote == 'A') countA++;
          if (vote == 'B') countB++;
        });

        // ② 勝敗の判定
        String loser = 'B';
        List<dynamic> loserPoints = mission['areaPointsB'] ?? [];

        if (countB > countA) {
          loser = 'A';
          loserPoints = mission['areaPointsA'] ?? [];
        } else if (countA == countB) {
          // もし同票だった場合は、GMの権限でランダム（コイントス）で容赦なく決める！
          if (Random().nextBool()) {
            loser = 'A';
            loserPoints = mission['areaPointsA'] ?? [];
          }
        }

        // ③ マップの縮小（負けたエリアを進入禁止エリアに追加）
        Map<String, dynamic> areaSettings = gameData['areaSettings'] ?? {};
        List forbiddenAreas = List.from(areaSettings['forbiddenAreas'] ?? []);
        
        if (loserPoints.isNotEmpty) {
          forbiddenAreas.add({
            'points': loserPoints,
            'name': '敗北エリア$loser', // 管理用の名前
          });
        }
        areaSettings['forbiddenAreas'] = forbiddenAreas;

        // ④ データベースを更新してマップを真っ赤に染める
        await gameRef.update({
          'activeMission': null,
          // ★修正: "areaSettings" 全体ではなく、"forbiddenAreas" だけをピンポイントで追加・更新！
          'areaSettings.forbiddenAreas': forbiddenAreas, 
          'hunterBoxes': [], 
        });

        // ⑤ サバイバー全員に絶望（あるいは歓喜）の結果発表を通知！
        String resultBody = "【 投票結果発表 】\nエリアA: $countA票\nエリアB: $countB票\n\nよって、エリア$loser が『進入禁止エリア』となった！\nエリア$loser に残っている者は直ちに脱出せよ！";
        await gameRef.collection('messages').add({
          'title': "投票結果！",
          'body': resultBody,
          'type': 'INFO', // 赤い警告を出したい場合は 'ALERT' などに変更
          'toUid': 'ALL',
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        _notify("投票を集計し、エリア$loser を進入禁止に設定しました！");

      } else {
        // 投票以外の通常ミッションは、今まで通り看板を下ろすだけ
        await gameRef.update({
          'activeMission': null, 
          'hunterBoxes': []
        });
        _notify("ミッションを終了しました");
      }
    }

    // 密告や位置公開などの状態をリセット
    var p = await gameRef.collection('players').get();
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
  }

// ====================================================
  // 単価アップ処理（自由入力）
  // ====================================================
  Future<void> _increaseRewardRate() async {
    final TextEditingController rateCtrl = TextEditingController(text: "100");

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("単価アップ設定", style: TextStyle(color: Colors.yellow)),
        content: TextField(
          controller: rateCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "アップする額 (円/秒)",
            labelStyle: TextStyle(color: Colors.grey),
            prefixIcon: Icon(Icons.trending_up, color: Colors.yellow),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow, foregroundColor: Colors.black),
            onPressed: () async {
              int upAmount = int.tryParse(rateCtrl.text) ?? 100;
              Navigator.pop(context);
              await _executeIncreaseRate(upAmount);
            },
            child: const Text("決定"),
          )
        ],
      ),
    );
  }

  Future<void> _executeIncreaseRate(int upAmount) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
        DocumentSnapshot snap = await transaction.get(gameRef);
        if (!snap.exists) return;

        Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
        DateTime now = DateTime.now();
        DateTime lastChanged = (data['lastRateChangedAt'] as Timestamp?)?.toDate() ?? (data['startTime'] as Timestamp).toDate();
        double currentRate = (data['settings_moneyRate'] ?? 100).toDouble();
        double basePrize = (data['basePrize'] ?? 0).toDouble();
        
        int elapsed = now.difference(lastChanged).inSeconds;
        if (elapsed < 0) elapsed = 0;
        double newBasePrize = basePrize + (elapsed * currentRate);
        double newRate = currentRate + upAmount.toDouble(); // ★入力された額を加算！
        
        transaction.update(gameRef, {
          'basePrize': newBasePrize,
          'lastRateChangedAt': FieldValue.serverTimestamp(),
          'settings_moneyRate': newRate,
        });

        DocumentReference msgRef = gameRef.collection('messages').doc();
        transaction.set(msgRef, {
          'title': "賞金単価アップ！",
          'body': "ミッション成功等により、賞金単価が【 1秒 ${newRate.toInt()}円 】にアップした！",
          'type': 'SUCCESS',
          'toUid': 'ALL',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      _notify("賞金単価を$upAmount円アップしました！");
    } catch (e) {
      _notify("エラーが発生しました: $e");
    }
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
                "チェイサーBOX (地図配置)",
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
              const SizedBox(height: 10),
              _buildBtn(
                Icons.trending_up,
                "単価アップ (+100円/秒)",
                Colors.yellow,
                _increaseRewardRate,
              ),
            ],
          );
        },
      ),
    );
  }
}

