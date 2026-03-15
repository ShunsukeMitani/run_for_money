import 'dart:typed_data';
import 'dart:convert';
import 'dart:async'; // Timer用
import 'dart:math'; // Random用
import 'package:flutter/foundation.dart'; // Web判定(kIsWeb)用
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_lock_task/flutter_lock_task.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:geolocator/geolocator.dart'; // 位置情報
import 'map_screen.dart';
import 'login_screen.dart';
import 'mission_control_screen.dart';
import 'package:flutter/services.dart'; // バイブレーション用
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart'; // 着信音
import 'area_editor_screen.dart'; // ★これを一番上のimportのまとまりに追加
import 'package:vibration/vibration.dart'; // ★本物のバイブツール

class HomeScreen extends StatefulWidget {
  final String myRole;
  final String myName;
  final bool isSecureMode;

  const HomeScreen({
    super.key,
    required this.myRole,
    required this.myName,
    required this.isSecureMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final ImagePicker _picker = ImagePicker();
  bool _isConnected = true;
  final Set<String> _readMessageIds = {};
  bool _isLocked = false;
  bool _hasValidUserLoaded = false;
  
  bool _isIncomingCall = false;
  // ★追加：アプリが今「画面に表示されているか」を確実に記憶する変数
  bool _isAppInForeground = true; 

  final String _discordServerId = "1461039637505245225";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAppInForeground = true; // ★初期化
    _initNotifications();
    _setupMessageListener();
    FirebaseFirestore.instance
        .collection('.info')
        .doc('connected')
        .snapshots()
        .listen(
          (_) => setState(() => _isConnected = true),
          onError: (_) => setState(() => _isConnected = false),
        );

    Future.delayed(const Duration(seconds: 15), () {
      if (mounted &&
          !_hasValidUserLoaded &&
          widget.myRole != 'GAME MASTER' &&
          widget.myRole != 'DEVELOPER') {
        _forceLogout();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && _isLocked) {
      FlutterLockTask().stopLockTask();
    }
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ★リアルタイムに画面の状態を記録！
    _isAppInForeground = state == AppLifecycleState.resumed;

    if (state == AppLifecycleState.resumed) {
      _checkIfCallFinished();
    }
  }

  void _forceLogout() {
    FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (c) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _checkIfCallFinished() async {
    // ★追加：データベースの読み込み（着信画面の準備）が終わるまで2秒待機する！
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    if (_isIncomingCall) return; // 着信画面が出ているならストップ！

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    var doc = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(user.uid)
        .get();

    if (doc.exists && (doc.data() as Map)['isBusy'] == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("通話確認", style: TextStyle(color: Colors.white)),
          content: const Text(
            "Discord通話は終了しましたか？\n終了した場合は「はい」を押してステータスを戻してください。",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("いいえ (通話中)"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(dialogContext);
                _hangUp();
              },
              child: const Text("はい (終了)"),
            ),
          ],
        ),
      );
    }
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final String? payload = response.payload;
        
        if (payload != null && payload.contains('|')) {
          List<String> parts = payload.split('|');
          String channelId = parts[0];
          String fromUid = parts[1];
          String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          
          if (response.actionId == 'answer_id') {
            FlutterRingtonePlayer().stop();
            // ★修正：ダイアログが出ている時「だけ」画面を閉じる（エラー回避の絶対防壁）
            if (mounted && _isIncomingCall) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            _isIncomingCall = false;

            if (myUid.isNotEmpty) {
              await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                'type': 'CALL_ACCEPTED',
                'fromUid': myUid,
                'toUid': fromUid,
                'channelId': channelId,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
            await _launchDiscordChannel(channelId);

          } else if (response.actionId == 'decline_id') {
            FlutterRingtonePlayer().stop();
            // ★修正：こちらも同様
            if (mounted && _isIncomingCall) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            _isIncomingCall = false;

            if (myUid.isNotEmpty) {
              await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                'title': "通話拒否",
                'body': "相手が通話を拒否しました。",
                'type': 'CALL_DECLINED',
                'fromUid': myUid,
                'fromName': widget.myName,
                'toUid': fromUid,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
            await _hangUp(silent: true);
          }
        }
      },
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _setupMessageListener() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        var doc = snapshot.docs.first;
        var data = doc.data();
        String docId = doc.id;
        String myUid = FirebaseAuth.instance.currentUser!.uid;

        if (data['visibleTo'] != null && data['visibleTo'] != widget.myRole) {
          return;
        }

        if (data['toUid'] == myUid || data['toUid'] == "ALL") {
          if (data['fromUid'] != myUid) {
            if (data['createdAt'] != null) {
              int diff = DateTime.now().difference((data['createdAt'] as Timestamp).toDate()).inSeconds;
              
              // ★着信だけは「60秒間」有効にする！
              int timeLimit = (data['type'] == 'CALL_REQUEST') ? 60 : 5;

              if (diff < timeLimit) {
                // ★すでに処理したメッセージは弾く（ダブり防止の絶対防壁）
                if (_readMessageIds.contains(docId)) return;
                _readMessageIds.add(docId);

                bool isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
                bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;

                // 着信以外はここでバイブを鳴らす
                if (data['type'] != 'CALL_REQUEST') {
                  HapticFeedback.heavyImpact();
                }

                // 📞 【着信の場合】
                if (data['type'] == 'CALL_REQUEST' && data['toUid'] == myUid) {
                  
                  _showIncomingCallDialog(data); // 裏でも表でも絶対に着信ダイアログを出す

                  if (!isForeground && !isIOS) {
                    _showNotification(
                      "📞 着信",
                      "${data['fromName']} から着信中...",
                      isCall: true,
                      payload: "${data['channelId']}|${data['fromUid']}",
                    );
                  }
                } 
                // 📩 【それ以外の通知の場合】
                else {
                  if (isForeground && isIOS) {
                    FlutterRingtonePlayer().playNotification();
                  }

                  if (data['type'] == 'CALL_ACCEPTED' && data['toUid'] == myUid) {
                    Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name != null);
                    _launchDiscordChannel(data['channelId']);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("相手が応答しました！接続します...")));
                  } else if (data['type'] == 'CALL_DECLINED' && data['toUid'] == myUid) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        if (isForeground) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("拒否されました"),
                              content: const Text("相手が応答できませんでした。"),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
                            ),
                          );
                        } else {
                          if (!isIOS) _showNotification("通話拒否", "${data['fromName']} が通話を拒否しました");
                        }
                        
                      // ⬇️⬇️ ★ここから追加：発信者がキャンセルした時の処理 ⬇️⬇️
                      } else if (data['type'] == 'CALL_CANCELED' && data['toUid'] == myUid) {
                        if (_isIncomingCall) {
                          _isIncomingCall = false; // フラグを折る
                          Vibration.cancel(); // バイブを強制ストップ！
                          FlutterRingtonePlayer().stop(); // 着信音を強制ストップ！
                          Navigator.of(context, rootNavigator: true).pop(); // 着信ダイアログを強制的に閉じる！
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("相手が発信をキャンセルしました")),
                          );
                        }
                        // ★さらに最強のハッカー技：裏画面で出ている「着信バナー(ID: 999)」もOSに命令して強制消去する！
                        _notificationsPlugin.cancel(999);
                      // ⬆️⬆️ ★ここまで追加 ⬆️⬆️

                      } else {
                        if (!isIOS) _showNotification(data['title'] ?? "通知", data['body'] ?? "新しい情報があります");
                      }
                }
              }
            }
          }
        }
      }
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    _isIncomingCall = true;

    // ★修正：専用ツールを使った「絶対にサボらない」強力な着信バイブループ
    void startVibrationLoop() async {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        while (_isIncomingCall) {
          Vibration.vibrate(duration: 1000); // 1秒間、全力で震える！
          await Future.delayed(const Duration(seconds: 2)); // 2秒待つ（1秒震えて1秒休むペース）
        }
      }
    }
    startVibrationLoop(); // バイブ開始！

    FlutterRingtonePlayer().play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.electronic,
      looping: true,
      volume: 1.0,
      asAlarm: false,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("📞 着信", style: TextStyle(color: Colors.white)),
        content: Text(
          "${data['fromName']} から通話リクエストが来ています。",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            child: const Text("拒否", style: TextStyle(color: Colors.red)),
            onPressed: () {
              _isIncomingCall = false; // ループ停止フラグ
              Vibration.cancel(); // ★バイブを強制ストップ！
              FlutterRingtonePlayer().stop();
              Navigator.pop(dialogContext);
              FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                'title': "通話拒否",
                'body': "相手が通話を拒否しました。",
                'type': 'CALL_DECLINED',
                'fromUid': FirebaseAuth.instance.currentUser!.uid,
                'fromName': widget.myName,
                'toUid': data['fromUid'],
                'createdAt': FieldValue.serverTimestamp(),
              });
              _hangUp(silent: true);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("応答"),
            onPressed: () async {
              _isIncomingCall = false; // ループ停止フラグ
              Vibration.cancel(); // ★バイブを強制ストップ！
              FlutterRingtonePlayer().stop();
              Navigator.pop(dialogContext);
              String channelId = data['channelId'];

              await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                'type': 'CALL_ACCEPTED',
                'fromUid': FirebaseAuth.instance.currentUser!.uid,
                'toUid': data['fromUid'],
                'channelId': channelId,
                'createdAt': FieldValue.serverTimestamp(),
              });

              _launchDiscordChannel(channelId);
            },
          ),
        ],
      ),
    ).then((_) {
      _isIncomingCall = false;
      Vibration.cancel(); // ★ダイアログが消えた時も念のためストップ
      FlutterRingtonePlayer().stop();
    });
  }

  Future<void> _showNotification(String title, String body, {bool isCall = false, String? payload}) async {
    AndroidNotificationDetails androidDetails;

    if (isCall) {
      androidDetails = AndroidNotificationDetails(
        'call_channel_v5',
        '着信通知',
        channelDescription: '着信時のバナー表示用',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false, // Androidは別途鳴らすので無音
        enableVibration: true,
        vibrationPattern: Int64List.fromList(<int>[0, 1000, 1000, 1000, 1000, 1000, 1000, 1000]),
        actions: [
          const AndroidNotificationAction(
            'answer_id', 
            '応答', 
            titleColor: Color.fromARGB(255, 0, 255, 0),
            showsUserInterface: true, 
          ),
          const AndroidNotificationAction(
            'decline_id', 
            '拒否', 
            titleColor: Color.fromARGB(255, 255, 0, 0),
            showsUserInterface: true, 
          ),
        ],
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        'default_normal_channel_v3',
        'ゲーム通知',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
    }

    NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        // ★修正：iOSは裏画面でRingtonePlayerが死んでしまうため、通知バナー自体の音を鳴らす！
        presentSound: true, 
        presentBadge: true,
        presentAlert: true,
        // ★追加：iOSに「これはすぐに見るべき重要な通知だ！」とアピールする
        interruptionLevel: InterruptionLevel.timeSensitive, 
      ),
    );

    await _notificationsPlugin.show(
      isCall ? 999 : DateTime.now().millisecond,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  void _checkLockStatus(String status) {
    if (kIsWeb) return;

    if (!widget.isSecureMode) return;
    if (status == 'ACTIVE' && !_isLocked) {
      FlutterLockTask().startLockTask();
      _isLocked = true;
    } else if (status != 'ACTIVE' && _isLocked) {
      FlutterLockTask().stopLockTask();
      _isLocked = false;
    }
  }

  void _checkMissionTimeLimit(Map<String, dynamic> activeMission) async {
    if (activeMission.isEmpty) return;

    if (activeMission['endTime'] == null) return;
    Timestamp endTs = activeMission['endTime'];
    if (DateTime.now().isAfter(endTs.toDate())) {
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          DocumentReference gameRef = FirebaseFirestore.instance
              .collection('games')
              .doc('game_001');
          DocumentSnapshot gameSnap = await transaction.get(gameRef);
          if (!gameSnap.exists) return;

          Map<String, dynamic> data = gameSnap.data() as Map<String, dynamic>;
          if (data['activeMission'] == null) return;

          String penaltyType = activeMission['penaltyType'] ?? 'NONE';
          int penaltyCount = activeMission['penaltyHunterCount'] ?? 1;
          List clearedUids = activeMission['clearedUids'] ?? [];

          transaction.update(gameRef, {'activeMission': null});

          DocumentReference msgRef = FirebaseFirestore.instance
              .collection('games')
              .doc('game_001')
              .collection('messages')
              .doc();
          String failBody = "ミッション終了\n制限時間を過ぎたためミッションは終了した。";

          if (penaltyType == 'HUNTER_RELEASE') {
            failBody += "\n\n【ペナルティ発動】\nハンターが $penaltyCount 体 放出された！";
          } else if (penaltyType == 'LOCATION_EXPOSE') {
            failBody += "\n\n【ペナルティ発動】\n未クリア者の位置情報が公開される！";
          }

          transaction.set(msgRef, {
            'title': "ミッション終了",
            'body': failBody,
            'type': 'CAUGHT',
            'toUid': 'ALL',
            'createdAt': FieldValue.serverTimestamp(),
          });
        });

        String pType = activeMission['penaltyType'] ?? 'NONE';
        List cUids = activeMission['clearedUids'] ?? [];

        if (pType == 'LOCATION_EXPOSE') {
          var batch = FirebaseFirestore.instance.batch();
          var runners = await FirebaseFirestore.instance
              .collection('games')
              .doc('game_001')
              .collection('players')
              .where('role', isEqualTo: 'RUNNER')
              .where('status', isEqualTo: 'ALIVE')
              .get();

          for (var doc in runners.docs) {
            if (!cUids.contains(doc.id)) {
              batch.update(doc.reference, {'isExposed': true});
            }
          }
          await batch.commit();
        }
      } catch (e) {
        // エラー無視
      }
    }
  }

  // --- メイン機能メソッド群 ---

  Future<void> _launchDiscordChannel(String channelId) async {
    if (!kIsWeb) await _notificationsPlugin.cancel(0);
    final messenger = ScaffoldMessenger.of(context);

    if (!kIsWeb && _isLocked) {
      await FlutterLockTask().stopLockTask();
      setState(() => _isLocked = false);
    }

    // ★修正: アプリ用URL(discord://)とWeb用URL(https://)を用意
    final Uri appUrl = Uri.parse(
      "discord://discord.com/channels/$_discordServerId/$channelId",
    );
    final Uri webUrl = Uri.parse(
      "https://discord.com/channels/$_discordServerId/$channelId",
    );

    try {
      // まずDiscordアプリでの起動を試みる
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl, mode: LaunchMode.externalApplication);
      } else {
        // アプリがなければブラウザ(Safari/Chrome)で開く
        // ※ platformDefaultだとアプリ内ブラウザになることがあるため externalApplication を指定
        if (!await launchUrl(webUrl, mode: LaunchMode.externalApplication)) {
          throw '起動に失敗しました';
        }
      }
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text("Discordを開けませんでした")));
    }
  }

  Future<void> _hangUp({bool silent = false}) async {
    if (!kIsWeb) await _notificationsPlugin.cancel(0);
    final messenger = ScaffoldMessenger.of(context);
    String myUid = FirebaseAuth.instance.currentUser!.uid;
    var myDoc = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(myUid)
        .get();
    if (!myDoc.exists) return;

    String? partnerUid = (myDoc.data() as Map)['talkingWith'];

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(myUid)
        .update({'isBusy': false, 'talkingWith': null});
    if (partnerUid != null) {
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(partnerUid)
          .update({'isBusy': false, 'talkingWith': null});
    }
    if (!silent) {
      messenger.showSnackBar(const SnackBar(content: Text("通話を終了しました")));
    }
  }

  Future<void> _sendCallRequest(
    String targetName,
    String targetUid,
    String channelId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    String myUid = FirebaseAuth.instance.currentUser!.uid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference targetRef = FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('players')
            .doc(targetUid);
        DocumentSnapshot targetSnap = await transaction.get(targetRef);
        if (targetSnap.exists && (targetSnap.data() as Map)['isBusy'] == true) {
          throw "相手は他の人と通話中です";
        }
        DocumentReference myRef = FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('players')
            .doc(myUid);
        transaction.update(targetRef, {'isBusy': true, 'talkingWith': myUid});
        transaction.update(myRef, {'isBusy': true, 'talkingWith': targetUid});
      });

      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('messages')
          .add({
            'title': "📞 着信あり",
            'body': "${widget.myName} から通話リクエストが届いています",
            'type': 'CALL_REQUEST',
            'fromUid': myUid,
            'fromName': widget.myName,
            'toUid': targetUid,
            'channelId': channelId,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.green),
                const SizedBox(height: 20),
                Text(
                  "$targetName を呼び出し中...",
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                const Text(
                  "相手が応答すると自動で切り替わります",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text("キャンセル", style: TextStyle(color: Colors.red)),
                onPressed: () async { // ★非同期処理(async)を追加
                  Navigator.pop(ctx); // 自分の画面のダイアログを閉じる

                  // ★追加：相手の着信（バイブ・音・画面）を強制停止させるキャンセル信号を発射！
                  await FirebaseFirestore.instance
                      .collection('games')
                      .doc('game_001')
                      .collection('messages')
                      .add({
                        'title': "着信キャンセル",
                        'body': "発信がキャンセルされました",
                        'type': 'CALL_CANCELED', 
                        'fromUid': myUid,
                        'toUid': targetUid,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                  _hangUp(); // 自分のステータスをリセットする
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openVoiceContactList(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "CONTACTS (Discord)",
          style: TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
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
              var docs = snapshot.data!.docs;
              String myUid = FirebaseAuth.instance.currentUser!.uid;

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (ctx, i) => const Divider(color: Colors.grey),
                itemBuilder: (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  bool isMe = docs[index].id == myUid;
                  String? channelId = data['discordId'];
                  bool isBusy = data['isBusy'] ?? false;

                  return ListTile(
                    leading: const Icon(
                      Icons.headset_mic,
                      color: Colors.white,
                      size: 40,
                    ),
                    title: Text(
                      data['name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: isBusy
                        ? const Text(
                            "通話中...",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Text(
                            channelId != null ? "待機可能" : "チャンネル未設定",
                            style: TextStyle(
                              color: channelId != null
                                  ? Colors.green
                                  : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                    trailing: isMe
                        ? const Text(
                            "YOU",
                            style: TextStyle(color: Colors.grey),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.call,
                              color: (isBusy || channelId == null)
                                  ? Colors.grey
                                  : Colors.purpleAccent,
                            ),
                            onPressed: (isBusy || channelId == null)
                                ? null
                                : () {
                                    Navigator.pop(dialogContext);
                                    _sendCallRequest(
                                      data['name'],
                                      docs[index].id,
                                      channelId,
                                    );
                                  },
                          ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  // --- 写真送信 (Base64版) ---
  Future<void> _takePhotoAndSend(
    BuildContext context, {
    bool isRevival = false,
  }) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 30, // 容量削減
      maxWidth: 600,
    );
    if (photo == null) return;

    // ★修正: 復活ミッション以外は送信しない
    if (!isRevival) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("撮影完了（ミッション対象外のため送信はされません）")),
        );
      }
      return;
    }

    final Uint8List bytes = await photo.readAsBytes();
    final String base64Image = base64Encode(bytes);
    String myUid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('photos')
        .add({
          'imageBase64': base64Image,
          'uploaderUid': myUid,
          'uploaderName': widget.myName,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'PENDING',
          'type': isRevival ? 'REVIVAL' : 'NORMAL',
        });

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(myUid)
        .update({'photoVerificationStatus': 'PENDING'});

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("写真を送信しました。審査を待ってください。")));
    }
  }

  // --- 投票機能 ---
  Widget _buildVotingWidget(Map<String, dynamic> missionData) {
    bool isGM =
        (widget.myRole == 'GAME MASTER' ||
        widget.myRole == 'ADMIN' ||
        widget.myRole == 'DEVELOPER');
    String optionA = missionData['optionA'] ?? "A";
    String optionB = missionData['optionB'] ?? "B";
    int votesA = missionData['votesA'] ?? 0;
    int votesB = missionData['votesB'] ?? 0;
    List votedUids = missionData['votedUids'] ?? [];
    bool hasVoted = votedUids.contains(FirebaseAuth.instance.currentUser!.uid);

    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const Text(
              "🗳️ 投票ミッション",
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              missionData['body'] ?? "",
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            if (hasVoted)
              const Text(
                "投票済みです",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () => _vote('A'),
                      child: Column(
                        children: [
                          Text(optionA),
                          Text(
                            isGM ? "$votesA票" : "?? 票",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () => _vote('B'),
                      child: Column(
                        children: [
                          Text(optionB),
                          Text(
                            isGM ? "$votesB票" : "?? 票",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _vote(String option) async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    var doc = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .get();
    if (doc.exists) {
      Map data = doc.data() as Map<String, dynamic>;
      Map votes =
          (data['activeMission'] != null &&
              data['activeMission']['votes'] != null)
          ? data['activeMission']['votes']
          : {};

      if (votes.containsKey(uid)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("既に投票済みです。変更はできません。"),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .update({'activeMission.votes.$uid': option});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("エリア$option に投票しました")));
      }
    }
  }

  // --- 密告・カメラメニュー ---
  void _openCameraMenu(BuildContext context, bool isInformerMission) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.qr_code_scanner,
                color: Colors.cyanAccent,
              ),
              title: const Text(
                "QRスキャン",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _openQRScanner(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
              title: const Text("写真撮影", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _takePhotoAndSend(context, isRevival: false);
              },
            ),
            if (isInformerMission)
              ListTile(
                leading: const Icon(
                  Icons.record_voice_over,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  "密告する (写真撮影)",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _startInformerProcess(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _startInformerProcess(BuildContext context) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 20,
      maxWidth: 400,
    );
    if (photo == null) return;
    String base64Image = base64Encode(await photo.readAsBytes());
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("誰を見つけましたか？", style: TextStyle(color: Colors.white)),
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
              var docs = snapshot.data!.docs
                  .where((d) => d.id != FirebaseAuth.instance.currentUser!.uid)
                  .toList();
              if (docs.isEmpty) {
                return const Text(
                  "他逃走者なし",
                  style: TextStyle(color: Colors.white),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var p = docs[index].data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(
                      p['name'],
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await FirebaseFirestore.instance
                          .collection('games')
                          .doc('game_001')
                          .collection('players')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .update({
                            'photoVerificationStatus': 'PENDING',
                            'lastPhoto': base64Image,
                            'reportTarget': p['name'],
                          });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${p['name']} を密告しました")),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // --- QRスキャナ (全画面) ---
  void _openQRScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text("QRスキャン"),
            backgroundColor: Colors.grey[900],
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (capture.barcodes.isNotEmpty) {
                String? code = capture.barcodes.first.rawValue;
                if (code != null) {
                  Navigator.pop(context); // 閉じてから処理
                  _scanToReviveProcess(code);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // --- QR読み取り処理 (使い捨てチェック) ---
  Future<void> _scanToReviveProcess(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    String myUid = FirebaseAuth.instance.currentUser!.uid;

    if (!code.startsWith("REVIVE:")) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("無効なQRコードです"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String codeId = code.split(":")[1];

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference codeRef = FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('revival_codes')
            .doc(codeId);
        DocumentSnapshot codeSnap = await transaction.get(codeRef);

        if (!codeSnap.exists) throw "無効なコードです";
        if (codeSnap['isUsed'] == true) throw "既に使用されたコードです";

        DocumentReference myRef = FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('players')
            .doc(myUid);

        // コード消費
        transaction.update(codeRef, {
          'isUsed': true,
          'usedBy': myUid,
          'usedAt': FieldValue.serverTimestamp(),
        });

        // 復活
        transaction.update(myRef, {'status': 'ALIVE'});
      });

      // 成功通知
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('messages')
          .add({
            'title': "復活！",
            'body': "${widget.myName} が復活ミッションにより牢獄から解放されました！",
            'type': 'SUCCESS',
            'createdAt': FieldValue.serverTimestamp(),
            'toUid': 'ALL',
          });
      messenger.showSnackBar(const SnackBar(content: Text("復活しました！逃走再開！")));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // --- 密告(地図版) メニュー ---
  void _openInformerMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "通報ターゲット選択",
          style: TextStyle(color: Colors.redAccent),
        ),
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
                  var d = snapshot.data!.docs[index];
                  if (d.id == FirebaseAuth.instance.currentUser!.uid) {
                    return const SizedBox();
                  }

                  return ListTile(
                    title: Text(
                      d['name'],
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.map, color: Colors.redAccent),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(
                            myRole: widget.myRole,
                            myName: widget.myName,
                            initialMode: 'SELECT_LOCATION',
                          ),
                        ),
                      );
                      if (result != null && result is LatLng) {
                        _sendInformerReport(d.id, d['name'], result);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ★修正: 密告送信 (通知追加)
  Future<void> _sendInformerReport(
    String targetUid,
    String targetName,
    LatLng reportLoc,
  ) async {
    String myName = widget.myName;
    try {
      // 1. 位置情報公開
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(targetUid)
          .update({
            'isExposed': true,
            'isReported': true,
            'reportedBy': myName,
            'reportLocation': {
              'lat': reportLoc.latitude,
              'lng': reportLoc.longitude,
            },
          });

      // 2. ★追加: 通知送信
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('messages')
          .add({
            'title': "密告情報",
            'body': "$myName からの密告！\n$targetName の位置情報が更新されました。",
            'type': 'MISSION',
            'toUid': 'ALL',
            'visibleTo': 'HUNTER', // ハンターのみ表示
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$targetName を密告しました。\n(ハンターにのみ位置が通知されます)")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("エラーが発生しました: $e")));
      }
    }
  }

  // --- メール ---
  void _openMailbox(BuildContext context) {
    bool isGM =
        (widget.myRole == 'GAME MASTER' ||
        widget.myRole == 'ADMIN' ||
        widget.myRole == 'DEVELOPER');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text(
              "INBOX",
              style: TextStyle(
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.grey[900],
            actions: [
              if (widget.myRole == 'RUNNER' || isGM)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.cyanAccent),
                  onPressed: () => _showComposeDialog(context),
                ),
            ],
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('games')
                .doc('game_001')
                .collection('messages')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text(
                    "メッセージはありません",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              String myUid = FirebaseAuth.instance.currentUser!.uid;
              var docs = snapshot.data!.docs.where((doc) {
                var d = doc.data() as Map<String, dynamic>;
                if (d['visibleTo'] != null && d['visibleTo'] != widget.myRole) {
                  return false;
                }
                String toUid = d['toUid'] ?? "ALL";
                String fromUid = d['fromUid'] ?? "";
                return toUid == "ALL" || toUid == myUid || fromUid == myUid;
              }).toList();
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    "メッセージはありません",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (ctx, i) =>
                    const Divider(height: 1, color: Colors.grey),
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  bool isRead = _readMessageIds.contains(doc.id);
                  IconData icon = Icons.mail;
                  Color color = Colors.orange;
                  if (data['type'] == 'CAUGHT') {
                    icon = Icons.warning;
                    color = Colors.red;
                  } else if (data['type'] == 'SUCCESS') {
                    icon = Icons.check_circle;
                    color = Colors.green;
                  } else if (data['type'] == 'MISSION') {
                    icon = Icons.flash_on;
                    color = Colors.yellow;
                  } else if (data['type'] == 'CHAT') {
                    icon = Icons.chat;
                    color = Colors.cyanAccent;
                  } else if (data['type'] == 'CALL_REQUEST') {
                    icon = Icons.phone_in_talk;
                    color = Colors.greenAccent;
                  } else if (data['type'] == 'PHOTO_RESULT') {
                    icon = Icons.photo_camera;
                    color = Colors.blueAccent;
                  } else if (data['fromName'] == 'GM' ||
                      data['fromName'] == 'GAME MASTER') {
                    icon = Icons.announcement;
                    color = Colors.purpleAccent;
                  }
                  String sender = data['fromName'] ?? "SYSTEM";
                  String title = data['title'] ?? "";
                  if (data['type'] == 'CHAT') title = "$sender: $title";

                  return ListTile(
                    tileColor: isRead ? Colors.black : Colors.grey[900],
                    leading: CircleAvatar(
                      backgroundColor: color,
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      data['body'] ?? "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: Text(
                      _formatDate(data['createdAt']),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: () {
                      setState(() => _readMessageIds.add(doc.id));
                      if (data['type'] == 'CALL_REQUEST') {
                        _showIncomingCallDialog(data);
                      } else {
                        _openMailDetail(context, data);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showComposeDialog(BuildContext context) {
    TextEditingController bodyCtrl = TextEditingController();
    String? selectedUid;
    bool sendToAll = false;
    bool isGM =
        (widget.myRole == 'GAME MASTER' ||
        widget.myRole == 'ADMIN' ||
        widget.myRole == 'DEVELOPER');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(
                isGM ? "GMメッセージ送信" : "メール作成",
                style: const TextStyle(color: Colors.cyanAccent),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isGM) ...[
                      Row(
                        children: [
                          const Text(
                            "送信先: ",
                            style: TextStyle(color: Colors.white),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: Text(
                                sendToAll ? "全員" : "個人",
                                style: TextStyle(
                                  color: sendToAll
                                      ? Colors.orangeAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              activeThumbColor: Colors.orangeAccent,
                              value: sendToAll,
                              onChanged: (val) {
                                setDialogState(() {
                                  sendToAll = val;
                                  if (sendToAll) selectedUid = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.grey),
                    ],

                    if (!sendToAll) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "宛先:",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('games')
                            .doc('game_001')
                            .collection('players')
                            .where('role', isEqualTo: 'RUNNER')
                            .where('status', isEqualTo: 'ALIVE')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox();
                          List<DropdownMenuItem<String>> items = [];
                          String myUid = FirebaseAuth.instance.currentUser!.uid;
                          for (var doc in snapshot.data!.docs) {
                            if (doc.id != myUid) {
                              var d = doc.data() as Map<String, dynamic>;
                              items.add(
                                DropdownMenuItem(
                                  value: doc.id,
                                  child: Text(
                                    d['name'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              );
                            }
                          }
                          if (selectedUid == null && items.isNotEmpty) {
                            selectedUid = items.first.value;
                          }
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                "送信可能な相手がいません",
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return DropdownButton<String>(
                            value: selectedUid,
                            dropdownColor: Colors.grey[800],
                            isExpanded: true,
                            items: items,
                            onChanged: (val) =>
                                setDialogState(() => selectedUid = val),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    TextField(
                      controller: bodyCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: "メッセージ内容",
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.cyanAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("キャンセル"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text("送信"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGM
                        ? Colors.purpleAccent
                        : Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (bodyCtrl.text.trim().isEmpty) return;
                    if (!sendToAll && selectedUid == null) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text("宛先を選択してください")),
                      );
                      return;
                    }
                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': isGM ? "GMからの通達" : "個別メッセージ",
                          'body': bodyCtrl.text.trim(),
                          'type': 'CHAT',
                          'fromUid': FirebaseAuth.instance.currentUser!.uid,
                          'fromName': isGM ? "GM" : widget.myName,
                          'toUid': sendToAll ? "ALL" : selectedUid,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                    if (context.mounted) Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(sendToAll ? "全員に送信しました" : "送信しました"),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openMailDetail(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text("MESSAGE"),
            backgroundColor: Colors.grey[900],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] ?? "",
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "From: ${data['fromName'] ?? 'SYSTEM'}",
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  _formatFullDate(data['createdAt']),
                  style: const TextStyle(color: Colors.grey),
                ),
                const Divider(color: Colors.grey, height: 30),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      data['body'] ?? "",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return "";
    DateTime d = ts.toDate();
    return "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  String _formatFullDate(Timestamp? ts) {
    if (ts == null) return "";
    DateTime d = ts.toDate();
    return "${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute}";
  }

  // --- 復活関連 ---
  void _showRevivalQRDialog() async {
    String codeId =
        DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
    String qrData = "REVIVE:$codeId";

    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('revival_codes')
        .doc(codeId)
        .set({
          'isUsed': false,
          'issuedBy': 'GM_MANUAL',
          'createdAt': FieldValue.serverTimestamp(),
        });

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("復活QRコード", style: TextStyle(color: Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "このQRを牢獄のプレイヤーに読み取らせてください\n(1回読み取ると無効になります)",
              style: TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(data: qrData, version: QrVersions.auto),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("閉じる"),
          ),
        ],
      ),
    );
  }

  // ★修正: 読み取り側で使い捨てチェック
  // ★修正: ダイアログではなく全画面スキャナを開く (キャンセルボタン対策)
  void _scanToRevive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text("復活QRスキャン"),
            backgroundColor: Colors.grey[900],
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (capture.barcodes.isNotEmpty) {
                String? code = capture.barcodes.first.rawValue;
                if (code != null) {
                  Navigator.pop(context); // 閉じてから処理
                  _scanToReviveProcess(code);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // ★修正: 不足していたメソッド定義を追加 (クラス内)
  void _openPhotoReviewList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PhotoReviewScreen()),
    );
  }

  // ★修正: 不足していたメソッド定義を追加 (クラス内)
  void _showRunnersList(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("SURVIVORS", style: TextStyle(color: Colors.green)),
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
              if (!snapshot.hasData) return const SizedBox();
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var d =
                      snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(
                      Icons.directions_run,
                      color: Colors.green,
                    ),
                    title: Text(
                      d['name'],
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  // --- ビルドメソッド群 ---

  Widget _buildMissionWidget(
    Map<String, dynamic> missionData,
    String? photoStatus,
  ) {
    if (widget.myRole == 'HUNTER') return const SizedBox();

    String type = missionData['type'] ?? "";
    String title = missionData['title'] ?? "MISSION";
    String desc = missionData['description'] ?? "";
    User? user = FirebaseAuth.instance.currentUser;
    String myUid = user != null ? user.uid : "";
    if (myUid.isEmpty) return const SizedBox();

    if (type == 'CODE') {
      List clearedUids = missionData['clearedUids'] ?? [];
      bool isCleared = clearedUids.contains(myUid);

      return Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.indigo.withOpacity(0.3),
          border: Border.all(color: Colors.indigoAccent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(desc, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),

            if (isCleared)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      "解除成功！あなたは安全です",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.dialpad),
                label: const Text("コードを入力"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigoAccent,
                ),
                onPressed: () async {
                  bool restricted =
                      missionData['isLocationRestricted'] ?? false;
                  if (restricted) {
                    var locData = missionData['inputLocation'];
                    if (locData != null) {
                      Position p = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high,
                      );
                      double dist = Geolocator.distanceBetween(
                        p.latitude,
                        p.longitude,
                        locData['lat'],
                        locData['lng'],
                      );

                      if (dist > 30) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "場所が違います！\n入力地点まであと ${(dist - 30).toInt()}m",
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }
                  }

                  _showCodeInputDialog(
                    context,
                    missionData['correctCode'] ?? "0000",
                  );
                },
              ),
          ],
        ),
      );
    } else if (type == 'REVIVAL') {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("🔥", style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFD4843E),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: Text(
                desc,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (photoStatus == 'APPROVED')
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                  ),
                  icon: const Icon(Icons.qr_code, size: 24),
                  label: const Text(
                    "復活QRを表示",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showRevivalQRDialog,
                ),
              )
            else if (photoStatus == 'PENDING')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.yellow),
                ),
                child: const Text(
                  "審査中... GMの承認を待ってください",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.yellow,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Column(
                children: [
                  if (photoStatus == 'REJECTED')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        "却下されました。再撮影してください。",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF66BB6A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 5,
                      ),
                      icon: const Icon(Icons.camera_alt, size: 24),
                      label: const Text(
                        "写真を撮影して送信",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () =>
                          _takePhotoAndSend(context, isRevival: true),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    } else if (type == 'VOTING') {
      return _buildVotingWidget(missionData);
    } else if (type == 'HUNTER_BOX_MAP') {
      bool isCleared = missionData['isCleared'] ?? false;
      return Card(
        color: Colors.purple.withOpacity(0.3),
        child: ListTile(
          leading: Icon(
            isCleared ? Icons.lock : Icons.lock_open,
            color: isCleared ? Colors.green : Colors.red,
            size: 40,
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text(
            "地図のBOXへ向かい、タップして封印せよ！",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: isCleared
              ? const Text("LOCKED", style: TextStyle(color: Colors.green))
              : const Icon(Icons.map, color: Colors.white),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    MapScreen(myRole: widget.myRole, myName: widget.myName),
              ),
            );
          },
        ),
      );
    } else if (type == 'INFORM') {
      return Container(
        margin: const EdgeInsets.all(15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.3),
          border: Border.all(color: Colors.red),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(desc, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text("ターゲット選択"),
              onPressed: () => _openInformerMenu(context),
            ),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  void _showCodeInputDialog(BuildContext context, String correctCode) {
    TextEditingController codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("コード入力", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: codeCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            letterSpacing: 5,
          ),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: "0000",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.indigoAccent),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigoAccent,
            ),
            onPressed: () async {
              if (codeCtrl.text == correctCode) {
                Navigator.pop(ctx);

                try {
                  await FirebaseFirestore.instance.runTransaction((
                    transaction,
                  ) async {
                    DocumentReference gameRef = FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001');
                    DocumentSnapshot gameSnap = await transaction.get(gameRef);
                    if (!gameSnap.exists) return;

                    Map<String, dynamic> data =
                        gameSnap.data() as Map<String, dynamic>;
                    Map<String, dynamic> activeMission = Map.from(
                      data['activeMission'] ?? {},
                    );

                    if (activeMission.isEmpty ||
                        activeMission['type'] != 'CODE') {
                      return;
                    }

                    List<dynamic> cleared = List.from(
                      activeMission['clearedUids'] ?? [],
                    );
                    String myUid = FirebaseAuth.instance.currentUser!.uid;
                    if (!cleared.contains(myUid)) {
                      cleared.add(myUid);
                      activeMission['clearedUids'] = cleared;
                    }

                    transaction.update(gameRef, {
                      'activeMission': activeMission,
                    });
                  });

                  // 完了チェック (トランザクション外で行う)
                  var runnersSnap = await FirebaseFirestore.instance
                      .collection('games')
                      .doc('game_001')
                      .collection('players')
                      .where('role', isEqualTo: 'RUNNER')
                      .where('status', isEqualTo: 'ALIVE')
                      .get();

                  var gameSnapAfter = await FirebaseFirestore.instance
                      .collection('games')
                      .doc('game_001')
                      .get();
                  var clearedList =
                      gameSnapAfter.data()?['activeMission']['clearedUids'] ??
                      [];

                  // 生存者数 <= クリア者数 ならミッション終了
                  if (clearedList.length >= runnersSnap.docs.length) {
                    
                    int bonusValue = gameSnapAfter.data()?['activeMission']['bonusRate'] ?? 100; // ★設定されたボーナス額を取得

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
                      double newRate = currentRate + bonusValue.toDouble(); // ★ボーナス額を足す！
                      
                      transaction.update(gameRef, {
                        'basePrize': newBasePrize,
                        'lastRateChangedAt': FieldValue.serverTimestamp(),
                        'settings_moneyRate': newRate,
                        'activeMission': null,
                      });
                    });

                    await FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .collection('messages')
                        .add({
                          'title': "ミッションクリア！",
                          'body': "全生存者がコード解除に成功！\nミッション阻止により、賞金単価が【 1秒あたり${bonusValue}円 】アップした！",
                          'type': 'SUCCESS',
                          'toUid': 'ALL',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                  } else {
                    // まだ終わっていない場合は自分だけ成功
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "解除成功！あなたは安全です。\n残り${runnersSnap.docs.length - clearedList.length}人が解除すれば完全クリアです。",
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  // エラーハンドリング
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("コードが違います！"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("解除実行"),
          ),
        ],
      ),
    );
  }

  // ★追加: 自首成功画面 (機能制限)
  Widget _buildSurrenderScreen(int prizeMoney) {
    // 獲得賞金のフォーマット
    String moneyStr;
    double m = prizeMoney.toDouble();
    if (m % 1 == 0) {
      moneyStr =
          "¥${m.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
    } else {
      String fixed = m.toStringAsFixed(1);
      List<String> parts = fixed.split('.');
      String intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      moneyStr = "¥$intPart.${parts[1]}";
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.yellow[800], // ゴールドっぽい色
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 100, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "自首成功",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "獲得賞金",
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              Text(
                moneyStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 50,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "ゲームから離脱しました。\n他のプレイヤーの状況は見れません。",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaughtScreen(Map<String, dynamic> gData) {
    DateTime startTime = (gData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime endTime = (gData['endTime'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.red[900],
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, _) {
                // ★この行が消えていたのが「nowがない」エラーの原因です！
                DateTime now = DateTime.now(); 
                
                Duration left = endTime.difference(now);
                String timeStr = left.isNegative
                    ? "00:00"
                    : "${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}";

                // ★単価が変わっても壊れない計算式
                double moneyRate = (gData['settings_moneyRate'] ?? 100).toDouble();
                double basePrize = (gData['basePrize'] ?? 0).toDouble();
                DateTime lastChanged = (gData['lastRateChangedAt'] as Timestamp?)?.toDate() ?? startTime;

                DateTime calcTime = now.isAfter(endTime) ? endTime : now;
                int elapsed = calcTime.difference(lastChanged).inSeconds;
                if (elapsed < 0) elapsed = 0;

                double currentMoney = basePrize + (elapsed * moneyRate);

                String moneyStr;
                if (currentMoney % 1 == 0) {
                  moneyStr =
                      "¥${currentMoney.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
                } else {
                  String fixed = currentMoney.toStringAsFixed(1);
                  List<String> parts = fixed.split('.');
                  String intPart = parts[0].replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]},',
                  );
                  moneyStr = "¥$intPart.${parts[1]}";
                }

                return Column(
                  children: [
                    const Text(
                      "TIME LIMIT",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "CURRENT PRIZE",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          moneyStr,
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 40,
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(blurRadius: 10, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock, size: 100, color: Colors.black),
                  SizedBox(height: 10),
                  Text(
                    "CAUGHT",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 50,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                      letterSpacing: 5,
                    ),
                  ),
                  Text(
                    "確 保 さ れ ま し た",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: Column(
                children: [
                  const Text(
                    "▼ 復活のチャンスがある場合はこちら ▼",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (!kIsWeb)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: Colors.greenAccent,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.greenAccent,
                        ),
                        label: const Text(
                          "復活QRを読み取る",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _scanToRevive,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text(
            "現在、通話中です",
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          ElevatedButton.icon(
            icon: const Icon(Icons.call_end),
            label: const Text("通話を終了して戻る"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _hangUp,
          ),
          const Text(
            "※Discordアプリ側でも退出してください",
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMailIcon() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('messages')
          .snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          String myUid = FirebaseAuth.instance.currentUser!.uid;
          count = snapshot.data!.docs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            String toUid = data['toUid'] ?? "ALL";
            String fromUid = data['fromUid'] ?? "";
            bool isRelevant =
                (toUid == "ALL" || toUid == myUid || fromUid == myUid);
            if (data['visibleTo'] != null && data['visibleTo'] != widget.myRole) {
              isRelevant = false;
            }
            return isRelevant && !_readMessageIds.contains(d.id);
          }).length;
        }
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            _AppIcon(
              icon: Icons.mail,
              label: "MAIL",
              color: Colors.orangeAccent,
              onTap: () => _openMailbox(context),
            ),
            if (count > 0)
              Positioned(
                right: 15,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "$count",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMissionTimer(Timestamp endTime) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        Duration diff = endTime.toDate().difference(DateTime.now());
        if (diff.isNegative || diff.inSeconds <= 0) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red),
          ),
          child: Text(
            "MISSION TIME: ${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}",
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusWidget(bool isGM) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox();
        }
        var data = snapshot.data!.data() as Map<String, dynamic>;
        String status = data['status'] ?? "WAITING";
        if (data.containsKey('startTime')) {
          DateTime start = (data['startTime'] as Timestamp).toDate();
          DateTime end = (data['endTime'] as Timestamp).toDate();

          if (data['activeMission'] != null) {
            _checkMissionTimeLimit(data['activeMission']);
          }

          return StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, _) {
              DateTime now = DateTime.now();
              String displayTime = "--:--";
              if (status == 'COUNTDOWN') {
                int diff = start.difference(now).inSeconds;
                if (diff <= 0) {
                  displayTime = "START";
                  if (isGM && diff < -2) {
                    FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({'status': 'ACTIVE'});
                  }
                } else {
                  displayTime = "READY $diff";
                }
              } else if (status == 'ACTIVE') {
                Duration remaining = end.difference(now);

                // ★追加: 制限時間が来たら自動でFINISHEDに更新
                if (remaining.isNegative || remaining.inSeconds == 0) {
                  remaining = Duration.zero;
                  FirebaseFirestore.instance
                      .collection('games')
                      .doc('game_001')
                      .update({'status': 'FINISHED'});
                }

                displayTime =
                    "${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}";
              }
              int money = 0;
              double currentMoney = 0.0;
              if (now.isAfter(start)) {
                // ★ステータス画面の正しい計算式
                DateTime calcTime = now.isAfter(end) ? end : now;
                double rate = (data['settings_moneyRate'] ?? 100).toDouble();
                double basePrize = (data['basePrize'] ?? 0).toDouble();
                DateTime lastChanged = (data['lastRateChangedAt'] as Timestamp?)?.toDate() ?? start;

                int elapsed = calcTime.difference(lastChanged).inSeconds;
                if (elapsed < 0) elapsed = 0;
                currentMoney = basePrize + (elapsed * rate);
              }

              String moneyStr;
              if (currentMoney % 1 == 0) {
                moneyStr =
                    "¥${currentMoney.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
              } else {
                String fixed = currentMoney.toStringAsFixed(1);
                List<String> parts = fixed.split('.');
                String intPart = parts[0].replaceAllMapped(
                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                  (Match m) => '${m[1]},',
                );
                moneyStr = "¥$intPart.${parts[1]}";
              }

              return Column(
                children: [
                  Text(
                    displayTime,
                    style: GoogleFonts.orbitron(
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                      color: status == 'COUNTDOWN'
                          ? Colors.red
                          : Colors.cyanAccent,
                    ),
                  ),
                  if (status == 'ACTIVE')
                    Text(
                      moneyStr,
                      style: GoogleFonts.orbitron(
                        fontSize: 30,
                        color: Colors.yellowAccent,
                      ),
                    ),
                ],
              );
            },
          );
        }
        return Text(
          "WAITING",
          style: GoogleFonts.orbitron(fontSize: 40, color: Colors.grey),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isGM =
        (widget.myRole == 'GAME MASTER' ||
        widget.myRole == 'ADMIN' ||
        widget.myRole == 'DEVELOPER');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.grey),
          onPressed: () async {
            if (!kIsWeb && _isLocked) FlutterLockTask().stopLockTask();
            await FirebaseAuth.instance.signOut();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (widget.isSecureMode)
                  const Icon(Icons.lock, size: 12, color: Colors.redAccent),
                const SizedBox(width: 5),
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 5),
                Text(
                  _isConnected ? "ONLINE" : "OFFLINE",
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .snapshots(),
        builder: (context, snapshot) {
          bool isInformerMission = false;
          Map<String, dynamic>? activeMission;
          String status = "WAITING";
          var gData = (snapshot.hasData && snapshot.data!.exists)
              ? snapshot.data!.data() as Map<String, dynamic>
              : <String, dynamic>{};

          if (gData.isNotEmpty) {
            status = gData['status'] ?? "WAITING";
            if (gData['activeMission'] != null) {
              activeMission = gData['activeMission'];
              if (activeMission!['type'] == 'INFORM') isInformerMission = true;
            }
          }
          _checkLockStatus(status);

          // ★追加: 結果画面への分岐 (Roleを渡す)
          if (status == 'FINISHED') {
            return GameResultScreen(myRole: widget.myRole);
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('games')
                .doc('game_001')
                .collection('players')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots(),
            builder: (context, mySnap) {
              if (mySnap.hasData && mySnap.data!.exists) {
                _hasValidUserLoaded = true;
              }

              if (_hasValidUserLoaded) {
                if (mySnap.hasData && !mySnap.data!.exists) {
                  if (widget.myRole != 'GAME MASTER' &&
                      widget.myRole != 'DEVELOPER') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _forceLogout();
                    });
                    return const Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                }
              } else {
                if (!mySnap.hasData || !mySnap.data!.exists) {
                  return const Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
              }

              bool amIBusy = false;
              String myStatus = "ALIVE";
              String? photoStatus;
              int surrenderedMoney = 0;

              if (mySnap.hasData && mySnap.data!.exists) {
                var d = mySnap.data!.data() as Map<String, dynamic>;
                amIBusy = d['isBusy'] ?? false;
                myStatus = d['status'] ?? "ALIVE";
                photoStatus = d['photoVerificationStatus'];
                surrenderedMoney = d['money'] ?? 0;
              }

              if (myStatus == 'CAUGHT') {
                return _buildCaughtScreen(gData);
              }
              if (myStatus == 'SURRENDERED') {
                return _buildSurrenderScreen(surrenderedMoney);
              }

              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.grey[900]!, Colors.black],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _buildStatusWidget(isGM),
                          if (amIBusy) _buildBusyWarning(),

                          if (activeMission != null)
                            _buildMissionWidget(activeMission, photoStatus),
                          if (activeMission != null &&
                              activeMission['endTime'] != null)
                            _buildMissionTimer(activeMission['endTime']),

                          const SizedBox(height: 30),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              mainAxisSpacing: 15,
                              crossAxisSpacing: 15,
                              children: [
                                _AppIcon(
                                  icon: Icons.map,
                                  label: "MAP",
                                  color: Colors.blueAccent,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MapScreen(
                                        myRole: widget.myRole,
                                        myName: widget.myName,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!kIsWeb)
                                  _AppIcon(
                                    icon: Icons.camera_alt,
                                    label: "CAMERA",
                                    color: Colors.greenAccent,
                                    onTap: () => _openCameraMenu(
                                      context,
                                      isInformerMission,
                                    ),
                                  ),
                                _AppIcon(
                                  icon: Icons.headset_mic,
                                  label: "VOICE",
                                  color: Colors.purpleAccent,
                                  onTap: () => _openVoiceContactList(context),
                                ),
                                _buildMailIcon(),
                                _AppIcon(
                                  icon: Icons.group,
                                  label: "RUNNERS",
                                  color: Colors.tealAccent,
                                  onTap: () => _showRunnersList(context),
                                ),
                                if (isGM) ...[
                                  _AppIcon(
                                    icon: Icons.settings,
                                    label: "SETTINGS",
                                    color: Colors.grey,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const SettingsAppScreen(),
                                      ),
                                    ),
                                  ),
                                  _AppIcon(
                                    icon: Icons.flash_on,
                                    label: "MISSION",
                                    color: Colors.redAccent,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const MissionControlScreen(),
                                      ),
                                    ),
                                  ),
                                  _AppIcon(
                                    icon: Icons.image_search,
                                    label: "PHOTO CHECK",
                                    color: Colors.blueGrey,
                                    onTap: () => _openPhotoReviewList(context),
                                  ),
                                ],
                                if (!kIsWeb)
                                  _AppIcon(
                                    icon: Icons.notifications_active,
                                    label: "通知設定",
                                    color: Colors.orangeAccent,
                                    onTap: () async {
                                      String myUid = FirebaseAuth.instance.currentUser!.uid;
                                      // ⚠️ 先ほどデプロイしたあなたのHosting URLに、 /?uid=$myUid を足したもの
                                      Uri url = Uri.parse("https://run-for-money-f042a.web.app//?uid=$myUid");
                                      
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  ),
                                if (widget.myRole == 'DEVELOPER')
                                  _AppIcon(
                                    icon: Icons.settings_ethernet,
                                    label: "CHANNELS",
                                    color: Colors.indigoAccent,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const DiscordManagementScreen(),
                                      ),
                                    ),
                                  ),
                                if (widget.myRole == 'RUNNER' &&
                                    isInformerMission)
                                  _AppIcon(
                                    icon: Icons.campaign,
                                    label: "密告",
                                    color: Colors.redAccent,
                                    onTap: () => _openInformerMenu(context),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AppIcon({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------
// ★追加クラス: 結果発表画面
// --------------------------------------------------------
class GameResultScreen extends StatelessWidget {
  // ★追加: Roleを受け取る
  final String myRole;
  const GameResultScreen({super.key, required this.myRole});

  String _fmtMoney(double m) {
    if (m % 1 == 0) {
      return "¥${m.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
    } else {
      String fixed = m.toStringAsFixed(1);
      List<String> parts = fixed.split('.');
      String intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return "¥$intPart.${parts[1]}";
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isGM =
        (myRole == 'GAME MASTER' || myRole == 'ADMIN' || myRole == 'DEVELOPER');

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .snapshots(),
        builder: (context, gameSnap) {
          if (!gameSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var gameData = gameSnap.data!.data() as Map<String, dynamic>;

          DateTime startTime = (gameData['startTime'] as Timestamp).toDate();
          DateTime endTime = (gameData['endTime'] as Timestamp).toDate();
          
          // ★結果発表画面の正しい計算式
          double rate = (gameData['settings_moneyRate'] ?? 100).toDouble();
          double basePrize = (gameData['basePrize'] ?? 0).toDouble();
          DateTime lastChanged = (gameData['lastRateChangedAt'] as Timestamp?)?.toDate() ?? startTime;

          int totalSeconds = endTime.difference(lastChanged).inSeconds;
          if (totalSeconds < 0) totalSeconds = 0;
          double maxPrize = basePrize + (totalSeconds * rate);


          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('games')
                .doc('game_001')
                .collection('players')
                .snapshots(),
            builder: (context, playerSnap) {
              if (!playerSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = playerSnap.data!.docs;
              var winners = docs
                  .where((d) => d['role'] == 'RUNNER' && d['status'] == 'ALIVE')
                  .toList();
              var surrenderers = docs
                  .where(
                    (d) =>
                        d['role'] == 'RUNNER' && d['status'] == 'SURRENDERED',
                  )
                  .toList();
              var caught = docs
                  .where(
                    (d) => d['role'] == 'RUNNER' && d['status'] == 'CAUGHT',
                  )
                  .toList();

              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        "GAME RESULT",
                        style: GoogleFonts.orbitron(
                          fontSize: 40,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 逃走成功者
                    const Text(
                      "🏆 ESCAPED (逃走成功)",
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(color: Colors.yellow),
                    if (winners.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          "なし",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ...winners.map((d) {
                      return ListTile(
                        leading: const Icon(
                          Icons.emoji_events,
                          color: Colors.yellow,
                        ),
                        title: Text(
                          d['name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: Text(
                          _fmtMoney(maxPrize),
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 30),

                    // 自首者
                    const Text(
                      "💰 SURRENDERED (自首成立)",
                      style: TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(color: Colors.lightBlueAccent),
                    if (surrenderers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          "なし",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ...surrenderers.map((d) {
                      double prize = (d['money'] ?? 0).toDouble();
                      return ListTile(
                        leading: const Icon(
                          Icons.monetization_on,
                          color: Colors.lightBlueAccent,
                        ),
                        title: Text(
                          d['name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        trailing: Text(
                          _fmtMoney(prize),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 30),

                    // 確保者
                    const Text(
                      "💀 CAUGHT (確保)",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(color: Colors.redAccent),
                    if (caught.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          "なし",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ...caught.map((d) {
                      return ListTile(
                        leading: const Icon(
                          Icons.cancel,
                          color: Colors.redAccent,
                        ),
                        title: Text(
                          d['name'],
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: const Text(
                          "¥0",
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }),

                    const SizedBox(height: 50),

                    // ★追加: GMなら設定画面へ飛べるボタンを表示
                    if (isGM)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Center(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 15,
                              ),
                            ),
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "設定・リセット画面へ (GM用)",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SettingsAppScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                        ),
                        onPressed: () {
                          // ログアウトしてタイトルへ
                          FirebaseAuth.instance.signOut();
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (c) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text("タイトルへ戻る"),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PhotoReviewScreen extends StatelessWidget {
  const PhotoReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("写真審査"),
        backgroundColor: Colors.grey[900],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('photos')
            .where('status', isEqualTo: 'PENDING') // 審査待ちのみ
            // ★修正: orderByを削除しました（これでグルグルが直ります）
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "審査待ちの写真はありません",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              String docId = doc.id;

              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    // Base64画像表示
                    if (data['imageBase64'] != null)
                      Image.memory(
                        base64Decode(data['imageBase64']),
                        height: 300,
                        fit: BoxFit.cover,
                        errorBuilder: (c, o, s) => const Icon(
                          Icons.broken_image,
                          size: 100,
                          color: Colors.grey,
                        ),
                      )
                    else if (data['url'] != null)
                      Image.network(data['url'], height: 300, fit: BoxFit.cover)
                    else
                      const SizedBox(
                        height: 300,
                        child: Center(
                          child: Text(
                            "画像データなし",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Text(
                            "From: ${data['uploaderName']}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                icon: const Icon(Icons.close),
                                label: const Text("却下"),
                                onPressed: () => _reviewPhoto(
                                  context,
                                  docId,
                                  false,
                                  data['uploaderUid'],
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text("承認 (QR発行)"),
                                onPressed: () => _reviewPhoto(
                                  context,
                                  docId,
                                  true,
                                  data['uploaderUid'],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _reviewPhoto(
    BuildContext context,
    String docId,
    bool isApproved,
    String uploaderUid,
  ) async {
    // 1. 写真のステータスを更新
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('photos')
        .doc(docId)
        .update({'status': isApproved ? 'APPROVED' : 'REJECTED'});

    // ★修正: プレイヤー自身のステータスも更新 (これがないと承認されてもボタンが変わらない)
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .doc(uploaderUid)
        .update({
          'photoVerificationStatus': isApproved ? 'APPROVED' : 'REJECTED',
        });

    if (isApproved) {
      // 毎回新しい使い捨てコードを発行
      String codeId =
          DateTime.now().millisecondsSinceEpoch.toString() +
          Random().nextInt(1000).toString();
      String qrData = "REVIVE:$codeId";

      // Firestoreに登録
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('revival_codes')
          .doc(codeId)
          .set({
            'isUsed': false,
            'issuedTo': uploaderUid,
            'issuedBy': 'GM_PHOTO_REVIEW',
            'createdAt': FieldValue.serverTimestamp(),
          });

      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(uploaderUid)
          .update({'hasRevivalQr': true});
      var gameDoc = await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .get();
      var activeMission = gameDoc.data()?['activeMission'] ?? {};
      int limit = activeMission['qrLimit'] ?? 999;
      int issued = activeMission['qrIssuedCount'] ?? 0;

      if (issued < limit) {
        await FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .update({'activeMission.qrIssuedCount': FieldValue.increment(1)});
        await FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('messages')
            .add({
              'title': "復活QRコード送付",
              'body':
                  "承認されました！このQRコードを使って仲間を復活させてください。\nCODE: $qrData", // ★修正: QRコードIDを埋め込む
              'type': 'QR_GIFT',
              'toUid': uploaderUid,
              'createdAt': FieldValue.serverTimestamp(),
            });
      } else {
        await FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('messages')
            .add({
              'title': "審査結果",
              'body': "写真は承認されましたが、QRコードの発行上限に達しました。",
              'type': 'PHOTO_RESULT',
              'toUid': uploaderUid,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }
    } else {
      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('messages')
          .add({
            'title': "写真審査結果",
            'body': "写真は却下されました。",
            'type': 'PHOTO_RESULT',
            'toUid': uploaderUid,
            'createdAt': FieldValue.serverTimestamp(),
          });
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(isApproved ? "承認しました" : "却下しました")));
    }
  }
}

// --------------------------------------------------------
// ★追加クラス: 設定画面
// --------------------------------------------------------
class SettingsAppScreen extends StatefulWidget {
  const SettingsAppScreen({super.key});
  @override
  State<SettingsAppScreen> createState() => _SettingsAppScreenState();
}

class _SettingsAppScreenState extends State<SettingsAppScreen> {
  final TextEditingController _timeCtrl = TextEditingController(text: "60");
  final TextEditingController _moneyCtrl = TextEditingController(text: "100");
  final TextEditingController _cntCtrl = TextEditingController(text: "10");
  final TextEditingController _intervalCtrl = TextEditingController(text: "5");
  final TextEditingController _delayCtrl = TextEditingController(text: "0");
  final TextEditingController _distCtrl = TextEditingController(text: "5"); // ★追加：GPSエコ距離
  bool _hunterVision = false;
  bool _allowSurrender = true;

  void _startGame() async {
    int min = int.tryParse(_timeCtrl.text) ?? 60;
    int cd = int.tryParse(_cntCtrl.text) ?? 10;
    DateTime now = DateTime.now();
    DateTime start = now.add(Duration(seconds: cd));
    DateTime end = start.add(Duration(minutes: min));

    await FirebaseFirestore.instance.collection('games').doc('game_001').update(
      {
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'status': 'COUNTDOWN',
        'settings_moneyRate': double.tryParse(_moneyCtrl.text) ?? 100.0,
        'basePrize': 0.0, 
        'lastRateChangedAt': Timestamp.fromDate(start),
        'settings_updateInterval': int.tryParse(_intervalCtrl.text) ?? 5,
        'settings_distanceFilter': int.tryParse(_distCtrl.text) ?? 5, // ★Firestoreに距離を保存
        'settings_hunterVision': _hunterVision,
        'settings_hunterDelay': int.tryParse(_delayCtrl.text) ?? 0,
        'settings_allowSurrender': _allowSurrender,
      },
    );
    var p = await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('players')
        .get();
    for (var d in p.docs) {
      d.reference.update({
        'status': 'ALIVE',
        'money': 0,
        'isReported': false,
        'photoVerificationStatus': null,
      });
    }
    if (mounted) Navigator.pop(context);
  }

  void _finishGame() async {
    await FirebaseFirestore.instance.collection('games').doc('game_001').update(
      {'status': 'FINISHED'},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ゲームを終了し、結果発表へ移行しました")));
      Navigator.pop(context);
    }
  }

  void _resetTimer() async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .update({
          'status': 'WAITING',
          'mission': '',
          'activeMission': FieldValue.delete(),
          'informerPoints': FieldValue.delete(),
          'hunterBoxes': FieldValue.delete(),
        });
    await _clearMessages();
    await _resetDiscordAssignments();
    messenger.showSnackBar(const SnackBar(content: Text("完全リセット完了")));
  }

  Future<void> _clearMessages() async {
    var msgs = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').get();
    for (var doc in msgs.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> _resetDiscordAssignments() async {
    var players = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get();
    for (var doc in players.docs) {
      await doc.reference.update({
        'discordId': null,
        'isBusy': false,
        'talkingWith': null,
        'photoVerificationStatus': null,
      });
    }
    var pool = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('discord_pool').get();
    for (var doc in pool.docs) {
      await doc.reference.update({
        'isUsed': false,
        'assignedTo': null,
        'assignedName': null,
      });
    }
  }

  void _clearPlayers() async {
    final messenger = ScaffoldMessenger.of(context);
    var p = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get();
    for (var d in p.docs) {
      d.reference.delete();
    }
    messenger.showSnackBar(const SnackBar(content: Text("データ消去完了")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("SETTINGS"),
        backgroundColor: Colors.grey[900],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildTF("ゲーム時間(分)", _timeCtrl),
          const SizedBox(height: 10),
          _buildTF("賞金単価", _moneyCtrl),
          const SizedBox(height: 10),
          _buildTF("カウントダウン(秒)", _cntCtrl),
          const SizedBox(height: 10),
          const Divider(color: Colors.grey),
          _buildTF("位置更新頻度(秒) [推奨:5~10]", _intervalCtrl),
          const SizedBox(height: 10),
          _buildTF("GPS更新距離(m) [推奨:3~10]", _distCtrl), // ★設定画面に距離入力欄を追加
          const SizedBox(height: 10),
          _buildTF("ハンター表示遅延(秒)", _delayCtrl),
          SwitchListTile(
            title: const Text("ハンターに位置を公開", style: TextStyle(color: Colors.white)),
            value: _hunterVision,
            activeThumbColor: Colors.redAccent,
            onChanged: (v) => setState(() => _hunterVision = v),
          ),
          SwitchListTile(
            title: const Text("自首を許可 (ボタン表示)", style: TextStyle(color: Colors.white)),
            subtitle: const Text("OFFにすると地図から自首ボタンが消えます", style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _allowSurrender,
            activeThumbColor: Colors.yellowAccent,
            onChanged: (v) => setState(() => _allowSurrender = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(15)),
            onPressed: _startGame,
            child: const Text("開始", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.all(15)),
            icon: const Icon(Icons.stop_circle),
            label: const Text("ゲーム終了 (結果発表へ)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _finishGame,
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.all(15)),
            icon: const Icon(Icons.map, color: Colors.white),
            label: const Text("エリア詳細設定 (マップ描画)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AreaEditorScreen()));
            },
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _resetTimer,
            child: const Text("リセット (Discord解放含む)", style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: _clearPlayers,
            child: const Text("全プレイヤー削除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildTF(String l, TextEditingController c) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: l,
      labelStyle: const TextStyle(color: Colors.grey),
    ),
  );
}

// --------------------------------------------------------
// ★追加クラス: Discordチャンネル管理画面
// --------------------------------------------------------
class DiscordManagementScreen extends StatefulWidget {
  const DiscordManagementScreen({super.key});
  @override
  State<DiscordManagementScreen> createState() =>
      _DiscordManagementScreenState();
}

class _DiscordManagementScreenState extends State<DiscordManagementScreen> {
  final TextEditingController _channelIdCtrl = TextEditingController();

  void _addChannel() async {
    String id = _channelIdCtrl.text.trim();
    if (id.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('discord_pool')
        .doc(id)
        .set({
          'isUsed': false,
          'assignedTo': null,
          'assignedName': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
    _channelIdCtrl.clear();
  }

  void _deleteChannel(String id) async {
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('discord_pool')
        .doc(id)
        .delete();
  }

  void _forceRelease(String id) async {
    await FirebaseFirestore.instance
        .collection('games')
        .doc('game_001')
        .collection('discord_pool')
        .doc(id)
        .update({'isUsed': false, 'assignedTo': null, 'assignedName': null});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("DISCORD CHANNELS"),
        backgroundColor: Colors.grey[900],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _channelIdCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Channel ID (数字)",
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _addChannel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigoAccent,
                  ),
                  child: const Text("追加"),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('games')
                  .doc('game_001')
                  .collection('discord_pool')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (ctx, i) =>
                      const Divider(color: Colors.grey),
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool isUsed = data['isUsed'] ?? false;
                    return ListTile(
                      leading: Icon(
                        isUsed ? Icons.headset_mic : Icons.headset_off,
                        color: isUsed ? Colors.red : Colors.green,
                      ),
                      title: Text(
                        doc.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        isUsed ? "使用中: ${data['assignedName']}" : "未使用 (待機中)",
                        style: TextStyle(
                          color: isUsed ? Colors.redAccent : Colors.grey,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUsed)
                            IconButton(
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.orange,
                              ),
                              onPressed: () => _forceRelease(doc.id),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => _deleteChannel(doc.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
