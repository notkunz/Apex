import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:relay_app/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ── App config ────────────────────────────────────────────────
const String kAppName = 'Apex';
const String kBroker = '4f05d94a1c4f4371b436887f2dd6f153.s1.eu.hivemq.cloud';
const int kPort = 8883;
const String kMqttUser = 'Kunzy';
const String kMqttPass = 'Kunznene1';
const Color kPrimary = Color(0xFF1A1A2E);
const Color kHighlight = Color(0xFFE94560);
const Color kBg = Color(0xFFF5F6FA);

const Map<String, Map<String, dynamic>> kDeviceTypes = {
  '1socket': {
    'label': '1 Socket',
    'relays': 1,
    'icon': Icons.power_outlined,
    'category': 'socket',
  },
  '2socket': {
    'label': 'Twin Socket',
    'relays': 2,
    'icon': Icons.electrical_services,
    'category': 'socket',
  },
  '4gang': {
    'label': '4 Gang',
    'relays': 4,
    'icon': Icons.grid_view_outlined,
    'category': 'socket',
  },
  '1switch': {
    'label': '1 Switch',
    'relays': 1,
    'icon': Icons.toggle_on_outlined,
    'category': 'switch',
  },
  '2switch': {
    'label': 'Twin Switch',
    'relays': 2,
    'icon': Icons.toggle_on_outlined,
    'category': 'switch',
  },
  'dimmer': {
    'label': 'Dimmer / Light',
    'relays': 0,
    'icon': Icons.light_outlined,
    'category': 'light',
  },
  'sensor_dht': {
    'label': 'Temp & Humidity',
    'relays': 0,
    'icon': Icons.thermostat_outlined,
    'category': 'sensor',
  },
  'sensor_motion': {
    'label': 'Motion Sensor',
    'relays': 0,
    'icon': Icons.sensors_outlined,
    'category': 'sensor',
  },
};

// ── Notification + Sound Service ──────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();
  String? _customAudioPath;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (details) {},
    );
    final prefs = await SharedPreferences.getInstance();
    _customAudioPath = prefs.getString('custom_audio_path');
    _initialized = true;
  }

  Future<void> setCustomAudio(String? path) async {
    _customAudioPath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('custom_audio_path', path);
    } else {
      await prefs.remove('custom_audio_path');
    }
  }

  String? get customAudioPath => _customAudioPath;

  Future<void> playAlarm() async {
    try {
      await _player.stop();
      if (_customAudioPath != null) {
        await _player.play(DeviceFileSource(_customAudioPath!));
      } else {
        await _player.play(AssetSource('sounds/siren.mp3'));
      }
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  Future<void> stopAlarm() async {
    await _player.stop();
  }

  Future<void> showMotionNotification(String deviceName) async {
    const androidDetails = AndroidNotificationDetails(
      'motion_channel',
      'Motion Alerts',
      channelDescription: 'Motion sensor alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: 0,
      title: 'Motion Detected!',
      body: '$deviceName detected movement',
      payload: 'details',
    );
  }
}

final notificationService = NotificationService();

// ── Main ──────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await notificationService.init();
  runApp(const ApexApp());
}

// ── Root ──────────────────────────────────────────────────────
class ApexApp extends StatelessWidget {
  const ApexApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kHighlight),
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }
          if (snapshot.hasData && snapshot.data!.emailVerified) {
            return const DevicesScreen();
          }
          if (snapshot.hasData && !snapshot.data!.emailVerified) {
            FirebaseAuth.instance.signOut();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

// ── Splash ────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt, size: 64, color: kHighlight),
            SizedBox(height: 16),
            Text(
              kAppName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(color: kHighlight),
          ],
        ),
      ),
    );
  }
}

// ── Login ─────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _isLogin = true;
  bool _showPass = false;
  String _error = '';
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (_isLogin) {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        if (!cred.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(
            () => _error = 'Please verify your email first. Check your inbox.',
          );
          return;
        }
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        await cred.user!.sendEmailVerification();
        await FirebaseAuth.instance.signOut();
        setState(() {
          _isLogin = true;
          _error =
              'Verification email sent to ${_emailCtrl.text.trim()}. Please verify before signing in.';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Something went wrong');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_resendCooldown > 0) return;
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      if (!cred.user!.emailVerified) {
        await cred.user!.sendEmailVerification();
        await FirebaseAuth.instance.signOut();
        setState(() {
          _error = 'Verification email resent! Check inbox and spam.';
          _resendCooldown = 60;
        });
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() {
            _resendCooldown--;
            if (_resendCooldown <= 0) t.cancel();
          });
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Something went wrong');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: kHighlight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.bolt,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      kAppName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Smart control at your fingertips',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isLogin ? 'Welcome back' : 'Create account',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin
                          ? 'Sign in to control your devices'
                          : 'Sign up to get started',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: kBg,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_showPass,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: kBg,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPass ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            if (_emailCtrl.text.trim().isEmpty) {
                              setState(
                                () => _error = 'Enter your email above first',
                              );
                              return;
                            }
                            try {
                              await FirebaseAuth.instance
                                  .sendPasswordResetEmail(
                                    email: _emailCtrl.text.trim(),
                                  );
                              setState(
                                () => _error =
                                    'Password reset email sent! Check your inbox.',
                              );
                            } on FirebaseAuthException catch (e) {
                              setState(
                                () => _error =
                                    e.message ?? 'Something went wrong',
                              );
                            }
                          },
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(fontSize: 12, color: kHighlight),
                          ),
                        ),
                      ),
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _resendCooldown > 0
                              ? null
                              : _resendVerification,
                          child: Text(
                            _resendCooldown > 0
                                ? 'Resend in ${_resendCooldown}s'
                                : 'Resend verification email',
                            style: TextStyle(
                              fontSize: 12,
                              color: _resendCooldown > 0
                                  ? Colors.grey[400]
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _error.contains('sent')
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error,
                          style: TextStyle(
                            fontSize: 12,
                            color: _error.contains('sent')
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kHighlight,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isLogin ? 'Sign in' : 'Sign up',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _isLogin = !_isLogin;
                        _error = '';
                      }),
                      child: Text(
                        _isLogin
                            ? "Don't have an account? Sign up"
                            : 'Already have an account? Sign in',
                        style: const TextStyle(color: kHighlight),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Devices Screen ────────────────────────────────────────────
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _user = FirebaseAuth.instance.currentUser!;
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  late MqttServerClient _statusClient;
  final Map<String, String> _deviceStatuses = {};
  final Map<String, String> _deviceFirmwareVersions = {};
  bool _mqttReady = false;
  String _filter = 'all';
  String _addType = '1socket';
  String _latestFirmwareVersion = '';
  final int _resendCooldown = 0;
  Timer? _cooldownTimer;

  Null get _emailCtrl => null;

  // ── Status MQTT ───────────────────────────────────────────
  Future<void> _initStatusClient(List<QueryDocumentSnapshot> devices) async {
    if (_mqttReady) return;
    try {
      _statusClient = MqttServerClient.withPort(
        kBroker,
        'apex_status_${DateTime.now().millisecondsSinceEpoch}',
        kPort,
      );
      _statusClient.secure = true;
      _statusClient.onBadCertificate = (dynamic a) => true;
      _statusClient.setProtocolV311();
      _statusClient.keepAlivePeriod = 60;
      _statusClient.connectionMessage = MqttConnectMessage()
          .withClientIdentifier('apex_status_watcher')
          .authenticateAs(kMqttUser, kMqttPass)
          .startClean();
      await _statusClient.connect();
      _mqttReady = true;

      for (final doc in devices) {
        final data = doc.data() as Map<String, dynamic>;
        final productId = data['productId'] as String;
        _statusClient.subscribe('apex/$productId/status', MqttQos.atLeastOnce);
        _statusClient.subscribe('apex/$productId/info', MqttQos.atLeastOnce);
      }

      _statusClient.updates!.listen((messages) {
        final msg = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          msg.payload.message,
        );
        final parts = messages[0].topic.split('/');
        if (parts.length < 3 || !mounted) return;
        final productId = parts[1];
        final topicType = parts[2];

        if (topicType == 'status') {
          setState(() => _deviceStatuses[productId] = payload);
        } else if (topicType == 'info') {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            final fw =
                data['fw'] as String? ?? data['firmware'] as String? ?? '';
            if (fw.isNotEmpty && mounted) {
              setState(() => _deviceFirmwareVersions[productId] = fw);
            }
          } catch (_) {}
        }
      });

      // fetch latest firmware version from Firestore
      try {
        final doc = await FirebaseFirestore.instance
            .collection('firmware')
            .doc('latest')
            .get();
        if (doc.exists && mounted) {
          setState(
            () => _latestFirmwareVersion =
                doc.data()?['version'] as String? ?? '',
          );
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Status client: $e');
    }
  }

  // ── Firmware helpers ──────────────────────────────────────
  Future<Map<String, dynamic>?> _getLatestFirmware() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('firmware')
          .doc('latest')
          .get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  void _sendOTAUpdate(String productId, String firmwareUrl) {
    if (!_mqttReady) return;
    debugPrint('Sending OTA to topic: apex/$productId/cmd');
    debugPrint('URL: $firmwareUrl');
    final b = MqttClientPayloadBuilder()..addString('OTA:$firmwareUrl');
    _statusClient.publishMessage(
      'apex/$productId/cmd',
      MqttQos.atLeastOnce,
      b.payload!,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Update started — device will reboot when done'),
        backgroundColor: Colors.teal,
        duration: Duration(seconds: 4),
      ),
    );
  }

  // ── Audio settings ────────────────────────────────────────
  void _showAudioSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Alert sound',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose sound for motion alerts',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: notificationService.customAudioPath == null
                        ? kHighlight.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.graphic_eq,
                    color: notificationService.customAudioPath == null
                        ? kHighlight
                        : Colors.grey[400],
                    size: 20,
                  ),
                ),
                title: const Text('Default siren'),
                subtitle: const Text(
                  'Built-in alarm sound',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: notificationService.customAudioPath == null
                    ? const Icon(Icons.check_circle, color: kHighlight)
                    : null,
                onTap: () async {
                  await notificationService.setCustomAudio(null);
                  setS(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: notificationService.customAudioPath != null
                        ? kHighlight.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.audio_file_outlined,
                    color: notificationService.customAudioPath != null
                        ? kHighlight
                        : Colors.grey[400],
                    size: 20,
                  ),
                ),
                title: const Text('Custom audio'),
                subtitle: Text(
                  notificationService.customAudioPath != null
                      ? notificationService.customAudioPath!.split('/').last
                      : 'Choose from your files',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: notificationService.customAudioPath != null
                    ? const Icon(Icons.check_circle, color: kHighlight)
                    : null,
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.audio,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    await notificationService.setCustomAudio(
                      result.files.single.path,
                    );
                    setS(() {});
                  }
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await notificationService.playAlarm();
                  await Future.delayed(const Duration(seconds: 3));
                  await notificationService.stopAlarm();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Test sound'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHighlight,
                  side: const BorderSide(color: kHighlight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _idCtrl.dispose();
    _nameCtrl.dispose();
    try {
      _statusClient.disconnect();
    } catch (_) {}
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAppUpdate();
  }

  Future<void> _checkAppUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app')
          .doc('latest')
          .get();
      if (!doc.exists || !mounted) return;

      final latestVersion = doc.data()?['version'] as String? ?? '';
      const currentVersion = '1.0.4'; // update this with every build
      final url = doc.data()?['url'] as String? ?? '';
      final notes = doc.data()?['notes'] as String? ?? '';
      final forceUpdate = doc.data()?['forceUpdate'] as bool? ?? false;

      if (latestVersion == currentVersion) return;

      showDialog(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (_) => AlertDialog(
          title: const Text(
            'Update available',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: kHighlight.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Version $latestVersion is available',
                  style: const TextStyle(
                    color: kHighlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  notes,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
              ],
              if (forceUpdate) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Colors.red[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                // open download link
                final uri = Uri.parse(url);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kHighlight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Download update'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  // ── Drawer item ───────────────────────────────────────────
  Widget _drawerItem(
    IconData icon,
    IconData iconSelected,
    String label,
    String value,
  ) {
    final selected = _filter == value;
    return ListTile(
      leading: Icon(
        selected ? iconSelected : icon,
        color: selected ? kHighlight : Colors.grey[600],
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? kHighlight : Colors.grey[700],
        ),
      ),
      tileColor: selected ? kHighlight.withOpacity(0.08) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: () {
        setState(() => _filter = value);
        Navigator.pop(context);
      },
    );
  }

  // ── Add device ────────────────────────────────────────────
  Future<void> _addDevice() async {
    final id = _idCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (id.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('devices')
        .doc(id)
        .set({
          'productId': id,
          'name': name.isEmpty ? id : name,
          'deviceType': _addType,
          'addedAt': FieldValue.serverTimestamp(),
        });
    _idCtrl.clear();
    _nameCtrl.clear();
    if (mounted) Navigator.pop(context);
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Add device',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kHighlight.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wifi_find, color: kHighlight),
              ),
              title: const Text(
                'Setup new device',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Configure a brand new Apex device',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push<Map<String, String>>(
                  context,
                  MaterialPageRoute(builder: (_) => const ProvisioningScreen()),
                );
                if (result != null && mounted) {
                  final id = result['deviceId']!;
                  final type = result['deviceType'] ?? '1socket';
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(_user.uid)
                      .collection('devices')
                      .doc(id)
                      .set({
                        'productId': id,
                        'name': id,
                        'deviceType': type,
                        'addedAt': FieldValue.serverTimestamp(),
                      });
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.keyboard, color: kPrimary),
              ),
              title: const Text(
                'Enter Product ID',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'I already have a Product ID',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _showManualAddDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showManualAddDialog() {
    setState(() => _addType = '1socket');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(
            'Add device',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _idCtrl,
                  decoration: InputDecoration(
                    labelText: 'Product ID',
                    hintText: 'e.g. APEX_A1B2C3',
                    prefixIcon: const Icon(Icons.qr_code),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'e.g. Living room',
                    prefixIcon: const Icon(Icons.label_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _addType,
                  decoration: InputDecoration(
                    labelText: 'Device type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: kDeviceTypes.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setS(() => _addType = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _addDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: kHighlight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Device options ────────────────────────────────────────
  void _showDeviceOptions(String productId, String currentName) {
    final renameCtrl = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              currentName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              productId,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),

            // Rename
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: kPrimary,
                  size: 20,
                ),
              ),
              title: const Text('Rename device'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text(
                      'Rename device',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    content: TextField(
                      controller: renameCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Device name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final newName = renameCtrl.text.trim();
                          if (newName.isEmpty) return;
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(_user.uid)
                              .collection('devices')
                              .doc(productId)
                              .update({'name': newName});
                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              },
            ),

            const Divider(),

            // Firmware update
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.system_update_outlined,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              title: const Text('Update firmware'),
              subtitle: Text(
                _deviceFirmwareVersions[productId] != null
                    ? 'Current: v${_deviceFirmwareVersions[productId]}'
                    : 'Tap to check for updates',
                style: const TextStyle(fontSize: 12),
              ),
              trailing:
                  _deviceFirmwareVersions[productId] != null &&
                      _latestFirmwareVersion.isNotEmpty &&
                      _deviceFirmwareVersions[productId] !=
                          _latestFirmwareVersion
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'New!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              onTap: () async {
                Navigator.pop(context);
                final firmware = await _getLatestFirmware();
                if (firmware == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not check for updates'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }
                final latestVersion = firmware['version'] as String;
                final url = firmware['url'] as String;
                final notes = firmware['notes'] as String? ?? '';
                final currentVersion =
                    _deviceFirmwareVersions[productId] ?? 'Unknown';
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text(
                        'Firmware update',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Current',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      Text(
                                        'v$currentVersion',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward,
                                  color: Colors.teal,
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.teal[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Latest',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.teal[400],
                                        ),
                                      ),
                                      Text(
                                        'v$latestVersion',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              notes,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 16,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Device reboots after update. Takes ~30 seconds.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: currentVersion == latestVersion
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _sendOTAUpdate(productId, url);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            currentVersion == latestVersion
                                ? 'Up to date'
                                : 'Update now',
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),

            // Alert sound — always shown, applies globally
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.purple[400],
                  size: 20,
                ),
              ),
              title: const Text('Alert sound'),
              subtitle: Text(
                notificationService.customAudioPath != null
                    ? 'Custom audio set'
                    : 'Default siren',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showAudioSettings();
              },
            ),

            const Divider(),

            // Delete
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              title: const Text(
                'Remove device',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Remove device'),
                    content: Text('Remove "$currentName" from your account?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('users')
                              .doc(_user.uid)
                              .collection('devices')
                              .doc(productId)
                              .delete();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          kAppName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            fontSize: 20,
          ),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
              color: kPrimary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kHighlight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bolt,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    kAppName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _user.email ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    Icons.home_outlined,
                    Icons.home,
                    'All devices',
                    'all',
                  ),
                  _drawerItem(
                    Icons.power_outlined,
                    Icons.power,
                    'Sockets',
                    'socket',
                  ),
                  _drawerItem(
                    Icons.toggle_on_outlined,
                    Icons.toggle_on,
                    'Switches',
                    'switch',
                  ),
                  _drawerItem(
                    Icons.light_outlined,
                    Icons.light,
                    'Lights & Dimmer',
                    'light',
                  ),
                  _drawerItem(
                    Icons.thermostat_outlined,
                    Icons.thermostat,
                    'Sensors',
                    'sensor',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.shield_outlined,
                color: kPrimary,
                size: 20,
              ),
              title: const Text(
                'Legal & Rights',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kPrimary,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 18,
              ),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text(
                      'Legal',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '© 2026 Apex IoT. All rights reserved.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Terms of Use',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'By using the Apex app and connected devices, you agree to use this product only for lawful purposes. Apex IoT is not liable for any damages arising from misuse.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'We collect only your email address for authentication. Device data is transmitted securely. We do not sell or share your data.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Warranty',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Apex IoT devices come with a limited warranty against manufacturing defects. Not covered: improper wiring, incorrect voltage, or unauthorized modifications.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Contact',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'support@apexiot.com',
                            style: TextStyle(
                              fontSize: 12,
                              color: kHighlight,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(
                'Apex IoT v1.0.0',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_user.uid)
            .collection('devices')
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kHighlight),
            );
          }
          final all = snap.data?.docs ?? [];

          final shown = _filter == 'all'
              ? all
              : all.where((d) {
                  final type =
                      ((d.data() as Map)['deviceType'] as String?) ?? '1socket';
                  final category =
                      kDeviceTypes[type]?['category'] as String? ?? 'socket';
                  return category == _filter;
                }).toList();

          if (all.isNotEmpty) _initStatusClient(all);

          if (shown.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.device_hub, size: 72, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No devices yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a device',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: shown.length,
            itemBuilder: (ctx, i) {
              final data = shown[i].data() as Map<String, dynamic>;
              final productId = data['productId'] as String;
              final name = data['name'] as String;
              final type = data['deviceType'] as String? ?? '1socket';
              final info = kDeviceTypes[type] ?? kDeviceTypes['1socket']!;
              final status = _deviceStatuses[productId] ?? '';
              final isOnline =
                  status == 'ONLINE' ||
                  status == 'ON' ||
                  status == 'OFF' ||
                  status.startsWith('R') ||
                  status.startsWith('DIM:');

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: kPrimary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          info['icon'] as IconData,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? Colors.green : Colors.grey[400],
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info['label'] as String,
                        style: const TextStyle(
                          fontSize: 11,
                          color: kHighlight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        productId,
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.chevron_right, size: 20),
                      if (_deviceFirmwareVersions[productId] != null &&
                          _latestFirmwareVersion.isNotEmpty &&
                          _deviceFirmwareVersions[productId] !=
                              _latestFirmwareVersion)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Update',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[800],
                            ),
                          ),
                        )
                      else if (_deviceFirmwareVersions[productId] != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v${_deviceFirmwareVersions[productId]}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  // FIX 1: onTap was missing — users couldn't open devices
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => DeviceControlScreen(
                        productId: productId,
                        name: name,
                        deviceType: type,
                      ),
                    ),
                  ),
                  onLongPress: () => _showDeviceOptions(productId, name),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: kHighlight,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
      ),
    );
  }
}

// ── Provisioning Screen ───────────────────────────────────────
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});
  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  final _wifiNameCtrl = TextEditingController();
  final _wifiPassCtrl = TextEditingController();
  bool _sending = false;
  bool _showPass = false;
  String _status = '';
  bool _success = false;

  Future<void> _sendCredentials() async {
    final ssid = _wifiNameCtrl.text.trim();
    final pass = _wifiPassCtrl.text.trim();
    if (ssid.isEmpty) return;
    setState(() {
      _sending = true;
      _status = 'Sending to device...';
      _success = false;
    });
    try {
      final resp = await http
          .post(
            Uri.parse('http://192.168.4.1/api/configure'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'ssid=$ssid&pass=$pass',
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final deviceId = data['deviceId'] as String;
        final deviceType = data['deviceType'] as String;
        setState(() {
          _success = true;
          _status = 'Device configured! Product ID: $deviceId';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context, {
            'deviceId': deviceId,
            'deviceType': deviceType,
          });
        }
      } else {
        setState(() => _status = 'Device returned an error. Please try again.');
      }
    } catch (_) {
      setState(
        () => _status =
            'Could not reach device. Make sure you are connected to the Apex_XXXXXX WiFi network.',
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Setup new device'),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepCard(
              step: '1',
              title: 'Power on your Apex device',
              body:
                  'Plug in your device. It will create its own WiFi network when ready.',
            ),
            const SizedBox(height: 12),
            _StepCard(
              step: '2',
              title: 'Connect to Apex WiFi',
              body:
                  'Go to your phone WiFi settings and connect to "Apex_XXXXXX".\nPassword: apex1234',
            ),
            const SizedBox(height: 12),
            // Offline control card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: kHighlight,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.bolt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Skip setup — control offline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Already connected to the Apex hotspot? Turn off mobile data to avoid interference. Control your device right now without setting up WiFi.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OfflineControlScreen(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kHighlight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Control offline',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // WiFi setup card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: kHighlight,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '3',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Enter your home WiFi details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _wifiNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Your WiFi name',
                      prefixIcon: const Icon(Icons.wifi),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _wifiPassCtrl,
                    obscureText: !_showPass,
                    decoration: InputDecoration(
                      labelText: 'Your WiFi password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPass ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _success ? Colors.green[50] : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12,
                          color: _success
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _sending ? null : _sendCredentials,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kHighlight,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Configure device',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
}

class _StepCard extends StatelessWidget {
  final String step, title, body;
  const _StepCard({
    required this.step,
    required this.title,
    required this.body,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device Control Screen ─────────────────────────────────────
class DeviceControlScreen extends StatefulWidget {
  final String productId, name, deviceType;
  const DeviceControlScreen({
    super.key,
    required this.productId,
    required this.name,
    required this.deviceType,
  });
  @override
  State<DeviceControlScreen> createState() => _DeviceControlState();
}

class _DeviceControlState extends State<DeviceControlScreen> {
  late MqttServerClient _client;
  bool _connected = false;
  bool _isConnecting = false;
  String _statusText = 'Connecting...';
  late String cmdTopic;
  late String statusTopic;
  late String telemetryTopic;

  final List<bool> _states = [false, false, false, false];
  double _dimmerLevel = 0;
  double _dimmerDisplay = 0;
  Map<String, dynamic> _sensorData = {};

  int get _count => kDeviceTypes[widget.deviceType]?['relays'] as int? ?? 1;
  bool get _isDimmer => widget.deviceType == 'dimmer';
  bool get _isSensor => widget.deviceType.startsWith('sensor_');

  @override
  void initState() {
    super.initState();
    cmdTopic = 'apex/${widget.productId}/cmd';
    statusTopic = 'apex/${widget.productId}/status';
    telemetryTopic = 'apex/${widget.productId}/telemetry';
    _restoreStates();
    _connect();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _saveStates() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'states_${widget.productId}';
    if (_isDimmer) {
      await prefs.setDouble('dim_${widget.productId}', _dimmerLevel);
    } else {
      await prefs.setStringList(key, _states.map((e) => e.toString()).toList());
    }
  }

  Future<void> _restoreStates() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDimmer) {
      final level = prefs.getDouble('dim_${widget.productId}') ?? 0;
      if (mounted) {
        setState(() {
          _dimmerLevel = level;
          _dimmerDisplay = level;
        });
      }
    } else {
      final key = 'states_${widget.productId}';
      final saved = prefs.getStringList(key);
      if (saved != null && mounted) {
        setState(() {
          for (int i = 0; i < saved.length && i < 4; i++) {
            _states[i] = saved[i] == 'true';
          }
        });
      }
    }
  }

  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    if (mounted) setState(() => _statusText = 'Connecting...');
    try {
      _client = MqttServerClient.withPort(kBroker, 'apexapp', kPort);
      _client.secure = true;
      _client.onBadCertificate = (dynamic a) => true;
      _client.setProtocolV311();
      _client.keepAlivePeriod = 60;
      _client.connectTimeoutPeriod = 15000;
      _client.onConnected = _onConnected;
      _client.onDisconnected = _onDisconnected;
      _client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier('apexapp')
          .authenticateAs(kMqttUser, kMqttPass)
          .startClean();
      await _client.connect();
      _client.subscribe(statusTopic, MqttQos.atLeastOnce);
      if (_isSensor) _client.subscribe(telemetryTopic, MqttQos.atLeastOnce);
      _client.updates!.listen(_onMessage);
    } catch (e) {
      debugPrint('MQTT: $e');
      if (mounted) setState(() => _statusText = 'Disconnected');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No internet connection'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        });
      }
    } finally {
      _isConnecting = false;
      if (!_connected && mounted) {
        Future.delayed(const Duration(seconds: 5), _connect);
      }
    }
  }

  void _triggerMotionAlert() async {
    await notificationService.playAlarm();
    await notificationService.showMotionNotification(widget.name);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Motion Detected!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.name} has detected movement.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Text(
              DateTime.now().toString().substring(0, 19),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              notificationService.stopAlarm();
              Navigator.pop(context);
            },
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              notificationService.stopAlarm();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.volume_off, size: 16),
            label: const Text('Stop alarm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> msgs) {
    final payload = MqttPublishPayload.bytesToStringAsString(
      (msgs[0].payload as MqttPublishMessage).payload.message,
    );
    final topic = msgs[0].topic;
    if (!mounted) return;

    if (topic == telemetryTopic) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final wasMotion = _sensorData['motion'] as bool? ?? false;
        setState(() => _sensorData = data);
        final isMotion = data['motion'] as bool? ?? false;
        if (isMotion && !wasMotion) {
          _triggerMotionAlert();
        } else if (!isMotion && wasMotion) {
          notificationService.stopAlarm();
        }
      } catch (_) {}
      return;
    }

    if (payload == 'ONLINE') {
      setState(() => _statusText = 'Device connected');
    } else if (payload == 'OFFLINE') {
      setState(() => _statusText = 'Device disconnected');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device is disconnected'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      });
    } else if (_isDimmer && payload.startsWith('DIM:')) {
      final level = double.tryParse(payload.substring(4)) ?? 0;
      setState(() {
        _dimmerLevel = level;
        _dimmerDisplay = level;
        _saveStates();
      });
    } else if (_count == 1) {
      setState(() => _states[0] = payload == 'ON');
      _saveStates();
    } else if (payload.length >= 4 && payload[0] == 'R' && payload[2] == ':') {
      final idx = int.tryParse(payload[1]);
      if (idx != null && idx >= 1 && idx <= 4) {
        setState(() => _states[idx - 1] = payload.substring(3) == 'ON');
        _saveStates();
      }
    }
  }

  void _onConnected() {
    if (mounted) {
      setState(() {
        _connected = true;
        _statusText = 'Connected';
      });
    }
  }

  void _onDisconnected() {
    if (mounted) {
      setState(() {
        _connected = false;
        _statusText = 'Disconnected';
      });
    }
    if (!_isConnecting && mounted) {
      Future.delayed(const Duration(seconds: 5), _connect);
    }
  }

  void _send(int idx, bool on) {
    if (!_connected) return;
    final cmd = _count == 1
        ? (on ? 'ON' : 'OFF')
        : 'R${idx + 1}:${on ? "ON" : "OFF"}';
    final b = MqttClientPayloadBuilder()..addString(cmd);
    _client.publishMessage(cmdTopic, MqttQos.atLeastOnce, b.payload!);
    if (mounted) setState(() => _states[idx] = on);
    _saveStates();
  }

  void _sendDim(double level) {
    if (!_connected) return;
    final b = MqttClientPayloadBuilder()..addString('DIM:${level.round()}');
    _client.publishMessage(cmdTopic, MqttQos.atLeastOnce, b.payload!);
    if (mounted) setState(() => _dimmerLevel = level);
    _saveStates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              kDeviceTypes[widget.deviceType]?['label'] as String? ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connected ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _statusText,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_connected)
                    TextButton(
                      onPressed: _connect,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text(
                        'Reconnect',
                        style: TextStyle(fontSize: 12, color: kHighlight),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildUI()),
          ],
        ),
      ),
    );
  }

  Widget _buildUI() {
    if (_isSensor) return _sensorUI();
    if (_isDimmer) return _dimmerUI();
    if (_count == 1) return _singleUI();
    return _multiUI();
  }

  Widget _singleUI() {
    final on = _states[0];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _connected ? () => _send(0, !on) : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 56),
            decoration: BoxDecoration(
              color: on ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: on ? kPrimary : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.power_settings_new,
                  size: 72,
                  color: on ? kHighlight : Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  on ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: on ? Colors.white : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to toggle',
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? Colors.white38 : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ActionBtn(
                label: 'ON',
                active: on,
                color: kHighlight,
                onPressed: _connected ? () => _send(0, true) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionBtn(
                label: 'OFF',
                active: !on,
                color: kPrimary,
                onPressed: _connected ? () => _send(0, false) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _multiUI() {
    final isSwitch = widget.deviceType.contains('switch');
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _count,
      itemBuilder: (_, i) {
        final on = _states[i];
        return GestureDetector(
          onTap: _connected ? () => _send(i, !on) : null,
          child: Container(
            decoration: BoxDecoration(
              color: on ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: on ? kPrimary : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSwitch ? Icons.toggle_on : Icons.power_settings_new,
                  size: 40,
                  color: on ? kHighlight : Colors.grey[300],
                ),
                const SizedBox(height: 8),
                Text(
                  '${isSwitch ? "Switch" : "Socket"} ${i + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: on ? Colors.white70 : Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  on ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: on ? Colors.white : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SmallBtn(
                      label: 'ON',
                      active: on,
                      onPressed: _connected ? () => _send(i, true) : null,
                    ),
                    const SizedBox(width: 8),
                    _SmallBtn(
                      label: 'OFF',
                      active: !on,
                      onPressed: _connected ? () => _send(i, false) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dimmerUI() {
    final isOn = _dimmerDisplay > 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            color: isOn ? kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isOn ? kPrimary : Colors.grey[200]!,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.lightbulb,
                size: 80,
                color: isOn
                    ? Color.lerp(
                        Colors.yellow[200],
                        Colors.yellow[600],
                        _dimmerDisplay / 100,
                      )
                    : Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                '${_dimmerDisplay.round()}%',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  color: isOn ? Colors.white : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isOn ? 'On' : 'Off',
                style: TextStyle(
                  fontSize: 14,
                  color: isOn ? Colors.white54 : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Icon(Icons.brightness_low, color: kHighlight, size: 20),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: kHighlight,
                  inactiveTrackColor: Colors.grey[200],
                  thumbColor: kHighlight,
                  overlayColor: kHighlight.withOpacity(0.15),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _dimmerDisplay,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_dimmerDisplay.round()}%',
                  onChanged: _connected
                      ? (v) => setState(() => _dimmerDisplay = v)
                      : null,
                  onChangeEnd: _connected ? _sendDim : null,
                ),
              ),
            ),
            const Icon(Icons.brightness_high, color: kHighlight, size: 20),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _presetBtn('Off', 0),
            _presetBtn('25%', 25),
            _presetBtn('50%', 50),
            _presetBtn('75%', 75),
            _presetBtn('Full', 100),
          ],
        ),
      ],
    );
  }

  Widget _presetBtn(String label, double value) {
    return GestureDetector(
      onTap: _connected
          ? () {
              setState(() => _dimmerDisplay = value);
              _sendDim(value);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _connected ? kPrimary.withOpacity(0.08) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _connected ? kPrimary : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _sensorUI() {
    if (widget.deviceType == 'sensor_dht') {
      final temp = _sensorData['temp'];
      final hum = _sensorData['hum'];
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _SensorCard(
                  icon: Icons.thermostat,
                  label: 'Temperature',
                  value: temp != null
                      ? '${(temp as num).toStringAsFixed(1)}°C'
                      : '---',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SensorCard(
                  icon: Icons.water_drop_outlined,
                  label: 'Humidity',
                  value: hum != null
                      ? '${(hum as num).toStringAsFixed(1)}%'
                      : '---',
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.update, size: 16, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Text(
                  'Updates every 10 seconds',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final motion = _sensorData['motion'] as bool? ?? false;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 56),
          decoration: BoxDecoration(
            color: motion ? Colors.orange[50] : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: motion ? Colors.orange : Colors.grey[200]!,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.motion_photos_on,
                size: 80,
                color: motion ? Colors.orange : Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                motion ? 'Motion Detected!' : 'No Motion',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: motion ? Colors.orange : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Read-only sensor',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Offline Control Screen ────────────────────────────────────
class OfflineControlScreen extends StatefulWidget {
  const OfflineControlScreen({super.key});
  @override
  State<OfflineControlScreen> createState() => _OfflineControlScreenState();
}

class _OfflineControlScreenState extends State<OfflineControlScreen> {
  static const String _baseUrl = 'http://192.168.4.1';

  String _deviceId = '';
  String _deviceType = '1socket';
  bool _loading = true;
  String _error = '';
  List<bool> _states = [false, false, false, false];
  double _dimLevel = 0;

  int get _count => kDeviceTypes[_deviceType]?['relays'] as int? ?? 1;
  bool get _isDimmer => _deviceType == 'dimmer';
  bool get _isSensor => _deviceType.startsWith('sensor_');

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final relays = (data['relays'] as List<dynamic>).cast<bool>();
        setState(() {
          _deviceId = data['deviceId'] as String;
          _deviceType = data['deviceType'] as String;
          _states = [...relays, false, false, false].take(4).toList();
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _error =
            'Cannot reach device.\nMake sure you are connected to the Apex hotspot.';
      });
    }
  }

  Future<void> _sendRelay(int idx, bool on) async {
    setState(() => _states[idx] = on);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/relay'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'relay=${idx + 1}&state=${on ? "ON" : "OFF"}',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      setState(() => _states[idx] = !on);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Command failed — check hotspot connection'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _sendDim(double level) async {
    setState(() => _dimLevel = level);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/dim'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'level=${level.round()}',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Command failed'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline control',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _deviceId.isEmpty ? 'Connecting...' : _deviceId,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchStatus),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kHighlight))
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchStatus,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kHighlight,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Offline mode — local hotspot control',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(child: _buildUI()),
                ],
              ),
            ),
    );
  }

  Widget _buildUI() {
    if (_isSensor) return _sensorPlaceholder();
    if (_isDimmer) return _dimmerUI();
    if (_count == 1) return _singleUI();
    return _multiUI();
  }

  Widget _singleUI() {
    final on = _states[0];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _sendRelay(0, !on),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 56),
            decoration: BoxDecoration(
              color: on ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: on ? kPrimary : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.power_settings_new,
                  size: 72,
                  color: on ? kHighlight : Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  on ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: on ? Colors.white : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to toggle',
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? Colors.white38 : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ActionBtn(
                label: 'ON',
                active: on,
                color: kHighlight,
                onPressed: () => _sendRelay(0, true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionBtn(
                label: 'OFF',
                active: !on,
                color: kPrimary,
                onPressed: () => _sendRelay(0, false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _multiUI() {
    final isSwitch = _deviceType.contains('switch');
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _count,
      itemBuilder: (_, i) {
        final on = _states[i];
        return GestureDetector(
          onTap: () => _sendRelay(i, !on),
          child: Container(
            decoration: BoxDecoration(
              color: on ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: on ? kPrimary : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSwitch ? Icons.toggle_on : Icons.power_settings_new,
                  size: 40,
                  color: on ? kHighlight : Colors.grey[300],
                ),
                const SizedBox(height: 8),
                Text(
                  '${isSwitch ? "Switch" : "Socket"} ${i + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: on ? Colors.white70 : Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  on ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: on ? Colors.white : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SmallBtn(
                      label: 'ON',
                      active: on,
                      onPressed: () => _sendRelay(i, true),
                    ),
                    const SizedBox(width: 8),
                    _SmallBtn(
                      label: 'OFF',
                      active: !on,
                      onPressed: () => _sendRelay(i, false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dimmerUI() {
    final isOn = _dimLevel > 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            color: isOn ? kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isOn ? kPrimary : Colors.grey[200]!,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.lightbulb,
                size: 80,
                color: isOn
                    ? Color.lerp(
                        Colors.yellow[200],
                        Colors.yellow[600],
                        _dimLevel / 100,
                      )
                    : Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                '${_dimLevel.round()}%',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  color: isOn ? Colors.white : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Icon(Icons.brightness_low, color: kHighlight, size: 20),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: kHighlight,
                  inactiveTrackColor: Colors.grey[200],
                  thumbColor: kHighlight,
                  overlayColor: kHighlight.withOpacity(0.15),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _dimLevel,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_dimLevel.round()}%',
                  onChanged: (v) => setState(() => _dimLevel = v),
                  onChangeEnd: _sendDim,
                ),
              ),
            ),
            const Icon(Icons.brightness_high, color: kHighlight, size: 20),
          ],
        ),
      ],
    );
  }

  Widget _sensorPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sensors, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Sensor data not available in offline mode',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback? onPressed;
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.active,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: active ? color : Colors.white,
      foregroundColor: active ? Colors.white : color,
      side: BorderSide(color: color),
      padding: const EdgeInsets.symmetric(vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: active ? 2 : 0,
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onPressed;
  const _SmallBtn({required this.label, required this.active, this.onPressed});
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: active ? kHighlight : Colors.white,
      foregroundColor: active ? Colors.white : kHighlight,
      side: const BorderSide(color: kHighlight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      elevation: active ? 2 : 0,
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    ),
  );
}

class _SensorCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _SensorCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Column(
      children: [
        Icon(icon, size: 36, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ],
    ),
  );
}
