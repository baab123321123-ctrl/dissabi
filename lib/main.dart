import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

// --- CONFIGURATION ---
const String SUPABASE_URL = 'https://qbvhrcugxczgmbxiujig.supabase.co';
const String SUPABASE_ANON_KEY = 'sb_publishable_h1EZ-EsuWyjCKSHAqI_vUQ_VmjEvaAC';
const String AGORA_APP_ID = '1a6c6bc141a845c784c1d79e717a1cd7';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
  runApp(const DissabiApp());
}

class DissabiApp extends StatelessWidget {
  const DissabiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dissabi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF313338),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF2B2D31), elevation: 0),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF5865F2)),
      ),
      home: Supabase.instance.client.auth.currentSession == null 
          ? const AuthScreen() 
          : const HomeScreen(),
    );
  }
}

// --- AUTH SCREEN ---
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleAuth(bool isSignUp) async {
    setState(() => _isLoading = true);
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final fakeEmail = '$username@dissabi.internal';

    try {
      final supabase = Supabase.instance.client;
      if (isSignUp) {
        final res = await supabase.auth.signUp(email: fakeEmail, password: password);
        if (res.user != null) {
          await supabase.from('profiles').insert({'id': res.user!.id, 'username': username});
        }
      } else {
        await supabase.auth.signInWithPassword(email: fakeEmail, password: password);
      }
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Dissabi', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF5865F2))),
            const SizedBox(height: 32),
            TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Kullanıcı Adı', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            if (_isLoading) const CircularProgressIndicator() else Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () => _handleAuth(false), child: const Text('Giriş Yap'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(onPressed: () => _handleAuth(true), child: const Text('Kayıt Ol'))),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// --- HOME SCREEN ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _pages = [const FriendsListTab(), const ProfileTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF2B2D31),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Sohbetler'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

// --- FRIENDS TAB ---
class FriendsListTab extends StatelessWidget {
  const FriendsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Dissabi Sohbetler')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('profiles').stream(primaryKey: ['id']),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data!.where((u) => u['id'] != myId).toList();

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                  child: user['avatar_url'] == null ? Text(user['username'][0].toUpperCase()) : null,
                ),
                title: Text(user['username']),
                trailing: IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceCallScreen(channelId: 'call_${user['id']}'))),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(receiverId: user['id'], receiverUsername: user['username']))),
              );
            },
          );
        },
      ),
    );
  }
}

// --- CHAT SCREEN ---
class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverUsername;
  const ChatScreen({super.key, required this.receiverId, required this.receiverUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  final _supabase = Supabase.instance.client;

  void _sendMsg() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await _supabase.from('messages').insert({
      'sender_id': _supabase.auth.currentUser!.id,
      'receiver_id': widget.receiverId,
      'content': text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = _supabase.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverUsername),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceCallScreen(channelId: 'call_${widget.receiverId}'))),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!.where((m) =>
                  (m['sender_id'] == myId && m['receiver_id'] == widget.receiverId) ||
                  (m['sender_id'] == widget.receiverId && m['receiver_id'] == myId)
                ).toList();

                return ListView.builder(
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final isMe = msgs[i]['sender_id'] == myId;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF5865F2) : const Color(0xFF383A40),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(msgs[i]['content'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _msgController, decoration: const InputDecoration(hintText: 'Mesaj yaz...', border: OutlineInputBorder()))),
                IconButton(icon: const Icon(Icons.send), onPressed: _sendMsg),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// --- PROFILE TAB ---
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 16),
            Text(user?.email?.split('@')[0] ?? 'Kullanıcı', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await supabase.auth.signOut();
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
              },
              child: const Text('Çıkış Yap'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- VOICE CALL SCREEN (AGORA) ---
class VoiceCallScreen extends StatefulWidget {
  final String channelId;
  const VoiceCallScreen({super.key, required this.channelId});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late RtcEngine _engine;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<void> _initAgora() async {
    await [Permission.microphone].request();
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(appId: AGORA_APP_ID));
    
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() => _joined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {},
      ),
    );

    await _engine.enableAudio();
    await _engine.joinChannel(
      token: '',
      channelId: widget.channelId,
      uid: 0,
      options: const ChannelMediaOptions(clientRoleType: ClientRoleType.clientRoleBroadcaster),
    );
  }

  @override
  void dispose() {
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1F22),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic, size: 80, color: _joined ? Colors.green : Colors.grey),
            const SizedBox(height: 24),
            Text(_joined ? 'Sesli Görüşme Bağlandı' : 'Bağlanıyor...', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 48),
            FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.call_end),
            )
          ],
        ),
      ),
    );
  }
}
