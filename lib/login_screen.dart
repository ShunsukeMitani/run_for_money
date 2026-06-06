import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  String _selectedRole = 'RUNNER';
  bool _isLoading = false;

  Future<void> _joinGame() async {
    String name = _nameCtrl.text.trim();
    String pass = _passCtrl.text.trim();

    // ★修正: GMとDEVELOPERは名前入力を無視して固定名にする
    if (_selectedRole == 'GAME MASTER') {
      name = "Game Master";
    } else if (_selectedRole == 'DEVELOPER') {
      name = "Developer";
    } else {
      // RUNNERとHUNTERは名前必須
      if (name.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("名前を入力してください")));
        return;
      }
    }

    // パスワードチェック (GMとDEVELOPERのみ)
    if (_selectedRole == 'DEVELOPER' && pass != 'admin') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Wrong Password")));
      return;
    }
    if (_selectedRole == 'GAME MASTER' && pass != '999') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Wrong Password")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInAnonymously();
      String uid = userCredential.user!.uid;

      // Discord割り当て: RUNNERのみ
      String? assignedDiscordId;
      if (_selectedRole == 'RUNNER') {
        assignedDiscordId = await _assignDiscordSlot(name, uid);
      }

      // Firestoreにプレイヤー情報を保存
      // ★ここで _selectedRole をそのまま保存するので、DEVELOPERは正しくDEVELOPERになります
      String myUid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(uid)
          .set({
            'name': name,
            'role': _selectedRole,
            'status': 'ALIVE',
            'joinedAt': FieldValue.serverTimestamp(),
            'money': 0,
            'discordId': assignedDiscordId,
            'isBusy': false,
            'talkingWith': null,
          });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            myRole: _selectedRole,
            myName: name,
            isSecureMode: (_selectedRole == 'RUNNER'),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 空いているDiscordチャンネルを探して割り当てる
  Future<String?> _assignDiscordSlot(
    String playerName,
    String playerUid,
  ) async {
    return FirebaseFirestore.instance.runTransaction((transaction) async {
      var querySnapshot = await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('discord_pool')
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      var docRef = querySnapshot.docs.first.reference;
      String channelId = querySnapshot.docs.first.id;

      transaction.update(docRef, {
        'isUsed': true,
        'assignedTo': playerUid,
        'assignedName': playerName,
      });

      return channelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 判定用：名前入力が必要なロールか？
    bool needsNameInput =
        (_selectedRole != 'GAME MASTER' && _selectedRole != 'DEVELOPER');
    // 判定用：パスワード入力が必要なロールか？
    bool needsPasswordInput =
        (_selectedRole == 'GAME MASTER' || _selectedRole == 'DEVELOPER');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "RUN FOR MONEY",
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.yellowAccent,
              ),
            ),
            const SizedBox(height: 40),

            // ロール選択
            DropdownButton<String>(
              value: _selectedRole,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              items: ['RUNNER', 'HUNTER', 'GAME MASTER', 'DEVELOPER'].map((
                String role,
              ) {
                return DropdownMenuItem(value: role, child: Text(role));
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedRole = val!);
              },
            ),
            const SizedBox(height: 20),

            // ★修正: GMとDEVELOPER以外の場合のみ名前入力を表示
            if (needsNameInput)
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "PLAYER NAME",
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.yellowAccent),
                  ),
                ),
              ),

            if (needsNameInput) const SizedBox(height: 20),

            // パスワード入力 (GM or DEVELOPERのみ)
            if (needsPasswordInput)
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "PASSWORD",
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),

            const SizedBox(height: 40),

            _isLoading
                ? const CircularProgressIndicator(color: Colors.yellowAccent)
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellowAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _joinGame,
                      child: const Text(
                        "JOIN GAME",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
