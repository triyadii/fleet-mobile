import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String baseUrl = 'https://dicotriyadi.site/fleet'; 
List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("No cameras available: $e");
  }
  
  if (!kIsWeb) {
    await initializeService();
  }
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', 
    'MY FOREGROUND SERVICE',
    description: 'This channel is used for important notifications.', 
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (!kIsWeb && Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Fleet Tracking',
      initialNotificationContent: 'Tracking in background',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Basic background tracking (without camera, since camera needs UI)
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      String? vehicleId = prefs.getString('vehicle_id');
      String serverUrl = prefs.getString('server_url') ?? baseUrl;

      if (token != null && vehicleId != null && vehicleId.isNotEmpty) {
        var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/api/telemetry'));
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': '*/*',
          'X-CSRF-TOKEN': '',
        });
        request.fields['vehicle_id'] = vehicleId;
        request.fields['lat'] = position.latitude.toString();
        request.fields['lng'] = position.longitude.toString();
        request.fields['speed'] = position.speed.toString();
        request.fields['timestamp'] = DateTime.now().toIso8601String();
        request.fields['snapshot'] = ''; // Empty snapshot in background

        await request.send();
      }
    } catch (e) {
      print("Error in background service: $e");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fleet Tracking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController(text: 'password');
  final _serverUrlCtrl = TextEditingController(text: baseUrl);
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      var url = Uri.parse('${_serverUrlCtrl.text}/api/login');
      var response = await http.post(url, headers: {
        'Content-Type': 'application/json',
        'Accept': '*/*',
        'X-CSRF-TOKEN': '',
      }, body: jsonEncode({
        'username': _usernameCtrl.text,
        'password': _passwordCtrl.text,
      }));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String token = data['access_token'] ?? '';
        String userId = data['user']['id'].toString();
        
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('server_url', _serverUrlCtrl.text);
        await prefs.setString('logged_in_user_id', userId);

        if (mounted) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (context) => const TrackingScreen()));
        }
      } else {
        _showError("Login failed: ${response.body}");
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Icon(
                  Icons.airport_shuttle,
                  size: 64,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Driver Portal",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                "Log in to start tracking your route",
                style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _serverUrlCtrl,
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : FilledButton(
                                onPressed: _login,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text("Login", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> with SingleTickerProviderStateMixin {
  String _vehicleId = '';
  bool _isRunning = false;
  Timer? _uiTimer;
  late AnimationController _animController;
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;

  // Map State
  final MapController _mapController = MapController();
  List<LatLng> _points = [];
  LatLng? _currentPos;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _loadUserAndInit();
  }
  
  Future<void> _loadUserAndInit() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _vehicleId = prefs.getString('logged_in_user_id') ?? '1';
    });
    
    // Find front camera default
    if (cameras.isNotEmpty) {
      _selectedCameraIndex = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
    }
    
    await _initCamera();
    await _fetchTelemetryData();
    _checkServiceStatus();
  }

  Future<void> _initCamera() async {
    try {
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(cameras[_selectedCameraIndex], ResolutionPreset.medium, enableAudio: false);
        await _cameraController?.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      print("Camera init error: $e");
    }
  }

  void _toggleCamera() async {
    if (cameras.length > 1) {
      setState(() {
        _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
      });
      await _initCamera();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _uiTimer?.cancel();
    _cameraController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    if (kIsWeb) return;
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    setState(() {
      _isRunning = isRunning;
    });
    if (isRunning) {
      _animController.repeat(reverse: true);
      _startUiTimer();
    }
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _sendTelemetryWithSnapshot();
      await _fetchTelemetryData(); // Fetch latest map data after sending
    });
  }

  Future<void> _fetchTelemetryData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      String serverUrl = prefs.getString('server_url') ?? baseUrl;

      var response = await http.get(
        Uri.parse('$serverUrl/api/telemetry/$_vehicleId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        var logs = data['data']['logs'] as List;

        if (logs.isNotEmpty) {
          List<LatLng> points = [];
          for (var log in logs) {
            points.add(LatLng(log['lat'], log['lng']));
          }

          var latest = logs.first;
          LatLng currentPos = LatLng(latest['lat'], latest['lng']);

          if (mounted) {
            setState(() {
              _points = points;
              _currentPos = currentPos;
            });
            _mapController.move(currentPos, 15);
          }
        }
      }
    } catch (e) {
      print("Error fetching telemetry map data: $e");
    }
  }

  Future<void> _sendTelemetryWithSnapshot() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      String? vehicleId = prefs.getString('vehicle_id');
      String serverUrl = prefs.getString('server_url') ?? baseUrl;

      if (token != null && vehicleId != null && vehicleId.isNotEmpty) {
        var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/api/telemetry'));
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': '*/*',
          'X-CSRF-TOKEN': '',
        });
        request.fields['vehicle_id'] = vehicleId;
        request.fields['lat'] = position.latitude.toString();
        request.fields['lng'] = position.longitude.toString();
        request.fields['speed'] = position.speed.toString();
        
        // Indonesian Time (WIB) which is UTC+7
        DateTime wibTime = DateTime.now().toUtc().add(const Duration(hours: 7));
        String formattedWib = "${wibTime.year.toString().padLeft(4, '0')}-${wibTime.month.toString().padLeft(2, '0')}-${wibTime.day.toString().padLeft(2, '0')}T${wibTime.hour.toString().padLeft(2, '0')}:${wibTime.minute.toString().padLeft(2, '0')}:${wibTime.second.toString().padLeft(2, '0')}+07:00";
        request.fields['timestamp'] = formattedWib;

        if (_cameraController != null && _cameraController!.value.isInitialized) {
          XFile image = await _cameraController!.takePicture();
          request.files.add(http.MultipartFile.fromBytes(
            'snapshot', 
            await image.readAsBytes(),
            filename: 'snapshot.jpg',
          ));
        } else {
          request.fields['snapshot'] = '';
        }

        var response = await request.send();
        if (response.statusCode == 201) {
          print("Telemetry with snapshot sent!");
        } else {
          print("Failed: ${response.statusCode}");
        }
      }
    } catch (e) {
      print("Tracking Error: $e");
    }
  }

  Future<void> _startTracking() async {
    // Request normal permissions first
    await [
      Permission.location,
      Permission.notification,
      Permission.camera,
    ].request();

    // Request background location separately (required for Android 11+)
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
    
    // Re-initialize camera if it was blocked before
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _initCamera();
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicle_id', _vehicleId);

    setState(() {
      _isRunning = true;
    });
    _animController.repeat(reverse: true);
    
    await _sendTelemetryWithSnapshot(); // Send immediate ping
    await _fetchTelemetryData();
    _startUiTimer();

    if (!kIsWeb) {
      final service = FlutterBackgroundService();
      await service.startService();
    }
  }

  Future<void> _stopTracking() async {
    _uiTimer?.cancel();
    setState(() {
      _isRunning = false;
    });
    _animController.stop();
    _animController.reset();

    if (!kIsWeb) {
      final service = FlutterBackgroundService();
      service.invoke("stopService");
    }
  }

  Future<void> _logout() async {
    _uiTimer?.cancel();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    String? serverUrl = prefs.getString('server_url');
    
    if (token != null && serverUrl != null) {
      await http.post(Uri.parse('$serverUrl/api/logout'), headers: {'Authorization': 'Bearer $token'});
    }
    
    await prefs.remove('token');
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
      appBar: AppBar(
        title: const Text("Fleet Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status and ID Row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: colorScheme.outlineVariant)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Text("Logged in as User ID: $_vehicleId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Container(
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _isRunning ? Colors.green.withOpacity(0.1 + (_animController.value * 0.2)) : Colors.grey.withOpacity(0.1),
                          border: Border.all(color: _isRunning ? Colors.green : Colors.grey, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            _isRunning ? "ONLINE" : "OFFLINE", 
                            style: TextStyle(fontWeight: FontWeight.bold, color: _isRunning ? Colors.green : Colors.grey)
                          ),
                        ),
                      );
                    }
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Map and Camera Side-by-Side (or stacked on small screens)
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    // Live Map Box
                    Container(
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _currentPos ?? const LatLng(-6.200000, 106.816666),
                            initialZoom: 14.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            )
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.fleet_manajemen',
                            ),
                            if (_points.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _points,
                                    color: Colors.blue,
                                    strokeWidth: 4.0,
                                  ),
                                ],
                              ),
                            if (_currentPos != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _currentPos!,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Live Camera Box
                    Stack(
                      children: [
                        Container(
                          height: 250,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colorScheme.outlineVariant, width: 2),
                            color: Colors.black87,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _cameraController != null && _cameraController!.value.isInitialized
                              ? SizedBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: 100, // Arbitrary base width
                                      height: 100 * _cameraController!.value.aspectRatio, // Inverted for portrait
                                      child: CameraPreview(_cameraController!),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                                      SizedBox(height: 8),
                                      Text("Camera Not Available", style: TextStyle(color: Colors.white54)),
                                    ],
                                  ),
                                ),
                          ),
                        ),
                        if (cameras.length > 1)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
                              onPressed: _toggleCamera,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            
            // Start/Stop Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                onPressed: _isRunning ? _stopTracking : _startTracking,
                style: FilledButton.styleFrom(
                  backgroundColor: _isRunning ? Colors.redAccent : colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle, size: 28),
                label: Text(_isRunning ? "STOP TRACKING" : "START TRACKING", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
