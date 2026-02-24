import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
// FontFeature用に必要

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // クリップボード用
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:path/path.dart' hide context;
import 'package:path_provider/path_provider.dart';
import 'package:poseidon/poseidon.dart';
import 'package:safe_device/safe_device.dart'; // Added
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Config ---
// 必要に応じてIPアドレスを変更してください
const String YOUR_LOCAL_IP = '192.168.11.40';
const String SERVER_URL = 'https://$YOUR_LOCAL_IP:3000';
// ---

late List<CameraDescription> cameras;

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<List<String>> _getDeviceUnsafeIssues() async {
  final issues = <String>[];

  if (await SafeDevice.isJailBroken) {
    issues.add("Jailbreak/Root化を検知しました。");
  }
  if (await SafeDevice.isDevelopmentModeEnable) {
    issues.add("開発者モードが有効です。");
  }
  // isRealDevice is generally reliable, but needs Platform.isAndroid guard for emulator detection context
  if (!await SafeDevice.isRealDevice) {
    if (Platform.isAndroid) {
      issues.add("エミュレーターまたは不正なデバイスを検知しました。");
    } else {
      // On iOS, a false here often indicates a modified or untrusted environment
      issues.add("不正なデバイスを検知しました。");
    }
  }

  // Remove duplicate messages, if any
  return issues.toSet().toList();
}

Future<void> main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("カメラの初期化エラー: $e");
    cameras = [];
  }

  await LocalDatabaseHelper.instance.database;

  runApp(const MyApp());
}

// --- Database Helper ---
class LocalDatabaseHelper {
  static final LocalDatabaseHelper instance = LocalDatabaseHelper._init();
  static Database? _database;

  LocalDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('zkp_verifier_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  capture_time TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  drone_id TEXT NOT NULL,
  image_path TEXT NOT NULL,
  hashes TEXT NOT NULL
)
    ''');
  }

  Future<int> createRecord(LocalRecord record) async {
    final db = await instance.database;
    return await db.insert('records', record.toMap());
  }

  Future<List<LocalRecord>> readAllRecords() async {
    final db = await instance.database;
    const orderBy = 'capture_time DESC';
    final result = await db.query('records', orderBy: orderBy);
    return result.map((json) => LocalRecord.fromMap(json)).toList();
  }
}

class LocalRecord {
  final int? id;
  final DateTime captureTime;
  final int maxDuration;
  final String droneId;
  final String imagePath;
  final Map<int, List<String>> hashesMap;

  LocalRecord({
    this.id,
    required this.captureTime,
    required this.maxDuration,
    required this.droneId,
    required this.imagePath,
    required this.hashesMap,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'capture_time': captureTime.toIso8601String(),
      'duration_seconds': maxDuration,
      'drone_id': droneId,
      'image_path': imagePath,
      'hashes': jsonEncode(
          hashesMap.map((key, value) => MapEntry(key.toString(), value))),
    };
  }

  static LocalRecord fromMap(Map<String, dynamic> map) {
    Map<int, List<String>> parsedHashes = {};
    try {
      final decoded = jsonDecode(map['hashes'] as String);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          parsedHashes[int.parse(key.toString())] =
              (value as List).map((e) => e.toString()).toList();
        });
      } else if (decoded is List) {
        final duration = map['duration_seconds'] as int;
        parsedHashes[duration] = decoded.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint("Hash parse error: $e");
    }

    return LocalRecord(
      id: map['id'] as int?,
      captureTime: DateTime.parse(map['capture_time'] as String),
      maxDuration: map['duration_seconds'] as int,
      droneId: map['drone_id'] as String,
      imagePath: map['image_path'] as String,
      hashesMap: parsedHashes,
    );
  }

  Map<String, dynamic> toJsonExport({int? specificDuration}) {
    Map<String, dynamic> proofs;

    if (specificDuration != null) {
      proofs = {};
      if (hashesMap.containsKey(specificDuration)) {
        proofs[specificDuration.toString()] = hashesMap[specificDuration];
      }
    } else {
      proofs = hashesMap.map((key, value) => MapEntry(key.toString(), value));
    }

    return {
      'id': id,
      'capture_time': captureTime.toIso8601String(),
      'drone_id': droneId,
      'image_filename': basename(imagePath),
      'exported_duration':
          specificDuration != null ? "${specificDuration}s" : "all",
      'proof_data': proofs,
    };
  }
}

// 位置情報履歴用クラス
class LocationLog {
  final DateTime timestamp;
  final LocationData location;

  LocationLog(this.timestamp, this.location);
}

// -----------------------

class SecurityCheckScreen extends StatefulWidget {
  final List<String> detectedIssues;
  const SecurityCheckScreen({super.key, required this.detectedIssues});

  @override
  State<SecurityCheckScreen> createState() => _SecurityCheckScreenState();
}

class _SecurityCheckScreenState extends State<SecurityCheckScreen> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.security_update_warning,
                  size: 80,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 24),
                Text(
                  'セキュリティ上の問題',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'このアプリは安全でない環境では実行できません。以下の問題が検出されました:',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
                const SizedBox(height: 24),
                // List of issues
                for (final issue in widget.detectedIssues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '• $issue',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('アプリを終了'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onError,
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZKP Verifier Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      // The actual home will be determined after security checks
      home: FutureBuilder<List<String>>(
        future: _getDeviceUnsafeIssues(),
        builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          } else if (snapshot.hasError) {
            // Handle error during security check (should ideally not happen)
            return SecurityCheckScreen(detectedIssues: [
              'セキュリティチェック中にエラーが発生しました: ${snapshot.error.toString()}'
            ]);
          } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            // Unsafe device, show security screen
            return SecurityCheckScreen(detectedIssues: snapshot.data!);
          } else {
            // Safe device, proceed to CameraScreen
            return const CameraScreen();
          }
        },
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final Location _location = Location();

  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _currentLocation;

  // 位置情報の履歴バッファ（過去の移動を記録するため）
  final List<LocationLog> _locationHistory = [];
  // 履歴の最大保持時間（古いものは捨てる）
  static const Duration _maxHistoryDuration = Duration(minutes: 2);

  static const String _targetDroneId = 'D8:3A:DD:E2:55:36';
  String _bleDisplayStatus = "ドローン検索中...";
  String _foundDroneId = "";
  StreamSubscription? _scanSubscription;
  DateTime? _lastDroneDetectionTime;
  final Duration _detectionHoldDuration = const Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (cameras.isNotEmpty) {
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );
      _initializeControllerFuture = _controller.initialize().then((_) {
        if (mounted) setState(() {});
      });
    } else {
      _initializeControllerFuture = Future.value();
    }

    _startBleScan();
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (cameras.isNotEmpty) _controller.dispose();
    _scanSubscription?.cancel();
    _locationSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller.value.isInitialized == false) return;
    if (state == AppLifecycleState.inactive) {
      _controller.dispose();
    } else if (state == AppLifecycleState.resumed) {}
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    try {
      await _location.enableBackgroundMode(enable: true);
    } catch (e) {
      debugPrint("Background mode error: $e");
    }

    // 1秒間隔で取得
    await _location.changeSettings(
      accuracy: LocationAccuracy.navigation,
      interval: 1000,
    );

    _locationSubscription =
        _location.onLocationChanged.listen((LocationData currentLocation) {
      final now = DateTime.now();

      // 履歴に追加
      _locationHistory.add(LocationLog(now, currentLocation));

      // 古い履歴を削除 (最大保持時間を超えたもの)
      _locationHistory.removeWhere(
          (log) => now.difference(log.timestamp) > _maxHistoryDuration);

      if (mounted) {
        setState(() {
          _currentLocation = currentLocation;
        });
      }
    });
  }

  Future<void> _startBleScan() async {
    if (await FlutterBluePlus.isAvailable == false) {
      if (!mounted) return;
      setState(() => _bleDisplayStatus = "Bluetooth不可");
      return;
    }

    try {
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.adapterState
            .where((state) => state == BluetoothAdapterState.on)
            .first;
      }
    } catch (e) {
      return;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      bool droneInCurrentScan =
          results.any((r) => r.device.remoteId.toString() == _targetDroneId);

      if (droneInCurrentScan) {
        _lastDroneDetectionTime = DateTime.now();
      }

      bool isDetected = _lastDroneDetectionTime != null &&
          DateTime.now().difference(_lastDroneDetectionTime!) <=
              _detectionHoldDuration;

      String newStatus = isDetected ? "接続中: $_targetDroneId" : "ドローン検索中...";
      String newFoundId = isDetected ? _targetDroneId : "";

      if (newStatus != _bleDisplayStatus || newFoundId != _foundDroneId) {
        if (mounted) {
          setState(() {
            _bleDisplayStatus = newStatus;
            _foundDroneId = newFoundId;
          });
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(days: 1),
      androidUsesFineLocation: true,
    );
  }

  // --- 改修箇所: 性能評価プロセスとレポート表示の統合 ---
  Future<void> _captureAndProcess() async {
    if (cameras.isEmpty) return;

    if (_foundDroneId.isEmpty) {
      _showErrorDialog("ドローンが近くに見つかりません。\n機体に近づいてください。");
      return;
    }
    if (_currentLocation == null) {
      _showErrorDialog("位置情報を取得中です。\n少々お待ちください。");
      return;
    }

    // 進行状況ダイアログ
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  Text("性能評価実行中(30回平均)...\n(10s~60s)",
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      await _initializeControllerFuture;
      final imageXFile = await _controller.takePicture();
      final captureTime = DateTime.now();

      // 撮影時点の現在地（補完用）
      final LocationData fallbackLocation = _currentLocation!;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'zkp_${captureTime.millisecondsSinceEpoch}.jpg';
      final savedImage =
          await File(imageXFile.path).copy('${appDir.path}/$fileName');

      // 撮影時刻を中心とした前後時間でハッシュ生成（性能計測含む）
      final result = await _generateAllHashes(
          captureTime, fallbackLocation, _locationHistory);

      await LocalDatabaseHelper.instance.createRecord(LocalRecord(
        captureTime: captureTime,
        maxDuration: 60,
        droneId: _foundDroneId,
        imagePath: savedImage.path,
        hashesMap: result.hashesMap,
      ));

      if (!mounted) return;
      Navigator.of(context).pop(); // 処理中ダイアログを閉じる

      // --- 性能評価レポートダイアログを表示 ---
      await _showPerformanceReport(result.performanceMetrics, () {
        // 「次へ進む」が押されたら検証画面へ遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VerificationScreen(
              imagePath: savedImage.path,
              captureTime: captureTime,
              hashesMap: result.hashesMap,
              droneId: _foundDroneId,
            ),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorDialog("エラーが発生しました: \n$e");
    }
  }

  // --- 改修箇所: 秒数ごとの処理時間を30回計測して平均化 ---
  Future<
          ({
            Map<int, List<String>> hashesMap,
            ProcessLog log,
            Map<int, int> performanceMetrics // 追加: 秒数 -> 平均ms
          })>
      _generateAllHashes(DateTime captureTime, LocationData fallbackLocation,
          List<LocationLog> history) async {
    final totalStopwatch = Stopwatch()..start();
    Map<int, List<String>> resultMap = {};
    Map<int, int> metrics = {};

    final durations = [10, 20, 30, 40, 50, 60];
    const int iterations = 30; // 30回試行

    // 各期間設定(duration)ごとにループ
    for (int d in durations) {
      final durationStopwatch = Stopwatch()..start(); // 個別計測開始
      List<String> lastHashes = []; // 最後の結果を保存

      // 30回繰り返して負荷計測
      for (int iter = 0; iter < iterations; iter++) {
        List<String> hashes = [];
        final halfDuration = d ~/ 2;

        for (int i = 0; i < d; i++) {
          final offsetSec = i - halfDuration;
          final timeOffset = Duration(seconds: offsetSec);
          final targetTime = captureTime.add(timeOffset);
          final targetTimeInt =
              BigInt.from(targetTime.millisecondsSinceEpoch ~/ 1000);

          LocationData targetLoc;

          if (history.isEmpty) {
            targetLoc = fallbackLocation;
          } else {
            LocationLog? closestLog;
            int minDiff = 999999999;

            for (var log in history) {
              final diff = (log.timestamp.millisecondsSinceEpoch -
                      targetTime.millisecondsSinceEpoch)
                  .abs();
              if (diff < minDiff) {
                minDiff = diff;
                closestLog = log;
              }
            }

            if (closestLog != null) {
              targetLoc = closestLog.location;
            } else {
              targetLoc = fallbackLocation;
            }
          }

          final lat = targetLoc.latitude!;
          final lon = targetLoc.longitude!;
          final points = _generateCircularPoints(lat, lon);

          for (final point in points) {
            final latInt = BigInt.from((point.$1 * 10000).round());
            final lonInt = BigInt.from((point.$2 * 10000).round());
            hashes.add(poseidon3([latInt, lonInt, targetTimeInt]).toString());
          }
        }
        lastHashes = hashes; // ループの最後に結果を保持
      }

      durationStopwatch.stop(); // 計測終了
      // 平均時間を計算 (総時間 / 試行回数)
      metrics[d] = durationStopwatch.elapsedMilliseconds ~/ iterations;
      resultMap[d] = lastHashes;
    }

    totalStopwatch.stop();
    return (
      hashesMap: resultMap,
      log: ProcessLog(
        name: ProcessName.hashGeneration,
        status: ProcessStatus.completed,
        duration: totalStopwatch.elapsed,
      ),
      performanceMetrics: metrics,
    );
  }

  // --- 性能評価レポートダイアログ (30回平均表示) ---
  Future<void> _showPerformanceReport(
      Map<int, int> metrics, VoidCallback onNext) async {
    // CSV形式の文字列を作成（コピー用）
    final csvBuffer = StringBuffer();
    csvBuffer.writeln("Duration(s),AvgTime(ms)");
    metrics.forEach((duration, ms) {
      csvBuffer.writeln("$duration,$ms");
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("性能評価レポート\n(30回平均)"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("各秒数における生成時間(平均):"),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.grey.shade400),
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1.5),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    children: const [
                      Padding(padding: EdgeInsets.all(8.0), child: Text("秒数")),
                      Padding(
                          padding: EdgeInsets.all(8.0), child: Text("平均処理時間")),
                    ],
                  ),
                  ...metrics.entries.map((e) {
                    return TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text("${e.key}s"),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text("${e.value} ms"),
                      ),
                    ]);
                  }),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "※ 上記は30回実行した平均値です。\n※ クリップボードにCSV形式でコピーして\n　エクセル等でグラフ化できます。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text("CSVをコピー"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvBuffer.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("結果をクリップボードにコピーしました")),
              );
            },
          ),
          FilledButton(
            child: const Text("次へ進む"),
            onPressed: () {
              Navigator.of(context).pop();
              onNext();
            },
          ),
        ],
      ),
    );
  }

  List<(double, double)> _generateCircularPoints(double lat, double lon) {
    final List<(double, double)> points = [];
    points.add((lat, lon));
    for (int i = 0; i < 8; i++) {
      final bearing = (2 * pi / 8) * i;
      points.add(_pointOnBearing(lat, lon, 15, bearing));
    }
    for (int i = 0; i < 16; i++) {
      final bearing = (2 * pi / 16) * i;
      points.add(_pointOnBearing(lat, lon, 30, bearing));
    }
    return points;
  }

  (double, double) _pointOnBearing(
      double lat, double lon, double dist, double bearing) {
    const R = 6371000;
    final latRad = lat * pi / 180;
    final lonRad = lon * pi / 180;
    final newLat = asin(sin(latRad) * cos(dist / R) +
        cos(latRad) * sin(dist / R) * cos(bearing));
    final newLon = lonRad +
        atan2(sin(bearing) * sin(dist / R) * cos(latRad),
            cos(dist / R) - sin(latRad) * sin(newLat));
    return (newLat * 180 / pi, newLon * 180 / pi);
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red),
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("閉じる"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (cameras.isEmpty) {
      return const Scaffold(body: Center(child: Text("カメラが利用できません")));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Camera'),
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_copy),
            tooltip: '保存済みデータ',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => const LocalHistoryScreen(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_controller);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _foundDroneId.isNotEmpty
                        ? Colors.green.withOpacity(0.8)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _foundDroneId.isNotEmpty ? Icons.link : Icons.link_off,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _bleDisplayStatus,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _currentLocation != null
                        ? "GPS捕捉中: ${DateFormat('HH:mm:ss').format(DateTime.now())}\nLat: ${_currentLocation!.latitude!.toStringAsFixed(5)}, Lon: ${_currentLocation!.longitude!.toStringAsFixed(5)}"
                        : "GPS検索中...",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: InkWell(
                onTap: _captureAndProcess,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocalHistoryScreen extends StatefulWidget {
  const LocalHistoryScreen({super.key});

  @override
  State<LocalHistoryScreen> createState() => _LocalHistoryScreenState();
}

class _LocalHistoryScreenState extends State<LocalHistoryScreen> {
  List<LocalRecord> _records = [];
  bool _isLoading = true;

  // 選択モード用
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await LocalDatabaseHelper.instance.readAllRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear(); // モード切替時に選択リセット
    });
  }

  void _toggleRecordSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // エクスポートオプションを表示するボトムシート
  void _showExportOptions() {
    final count = _isSelectionMode && _selectedIds.isNotEmpty
        ? "${_selectedIds.length}件の"
        : "全";

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 20),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                "$countデータを書き出し",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_zip),
              title: const Text('全ての秒数 (All)'),
              subtitle: const Text('全ての秒数パターンの証明データ'),
              onTap: () => _exportJson(null),
            ),
            const Divider(),
            ...[10, 20, 30, 40, 50, 60].map((duration) => ListTile(
                  leading: const Icon(Icons.timer),
                  title: Text('$duration秒データのみ'),
                  subtitle: Text('$duration秒時点の証明データのみ抽出'),
                  onTap: () => _exportJson(duration),
                )),
          ],
        );
      },
    );
  }

  // JSON生成とファイル共有処理
  Future<void> _exportJson(int? duration) async {
    Navigator.pop(context); // シートを閉じる

    if (_records.isEmpty) return;

    try {
      // 選択モード時は選択されたIDのみ、そうでなければ全件
      List<LocalRecord> targetRecords;
      if (_isSelectionMode && _selectedIds.isNotEmpty) {
        targetRecords =
            _records.where((r) => _selectedIds.contains(r.id)).toList();
      } else {
        targetRecords = _records;
      }

      if (targetRecords.isEmpty) return;

      // 1. JSONデータを生成
      final List<Map<String, dynamic>> jsonList = targetRecords
          .map((r) => r.toJsonExport(specificDuration: duration))
          .toList();

      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

      // 2. 一時ファイルとして保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final durationStr = duration == null ? 'all' : '${duration}s';
      final modeStr =
          _isSelectionMode && _selectedIds.isNotEmpty ? 'selected' : 'full';
      final fileName = 'zkp_${modeStr}_${durationStr}_$timestamp.json';
      final file = File('${tempDir.path}/$fileName');

      await file.writeAsString(jsonString);

      // 3. 共有シートを表示
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'ZKP証明データ ($durationStr) - ${targetRecords.length}件',
        subject: 'ZKP Records Export',
      );
    } catch (e) {
      debugPrint('Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('書き出しエラー: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isSelectionMode ? "${_selectedIds.length}件選択中" : "保存済みデータ"),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '選択モード',
              onPressed: _records.isEmpty ? null : _toggleSelectionMode,
            ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'JSONを書き出し',
            onPressed:
                (_records.isEmpty || (_isSelectionMode && _selectedIds.isEmpty))
                    ? null
                    : _showExportOptions,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("記録データはありません")
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _records.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final dateStr = DateFormat('yyyy/MM/dd HH:mm:ss')
                        .format(record.captureTime);
                    final isSelected = _selectedIds.contains(record.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: _isSelectionMode && isSelected
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2),
                            )
                          : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(8),
                        leading: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(record.imagePath),
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                            if (_isSelectionMode)
                              Positioned.fill(
                                child: Container(
                                  color: isSelected
                                      ? Colors.black45
                                      : Colors.transparent,
                                  child: isSelected
                                      ? const Icon(Icons.check_circle,
                                          color: Colors.white)
                                      : null,
                                ),
                              ),
                          ],
                        ),
                        title: Text(dateStr,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("ID: ${record.id} / ドローン: ${record.droneId}"),
                            Text("10s〜${record.maxDuration}s"),
                          ],
                        ),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleRecordSelection(record.id!);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VerificationScreen(
                                  imagePath: record.imagePath,
                                  captureTime: record.captureTime,
                                  hashesMap: record.hashesMap,
                                  droneId: record.droneId,
                                  isHistoryView: true,
                                ),
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                            _toggleRecordSelection(record.id!);
                          }
                        },
                        trailing: _isSelectionMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (val) =>
                                    _toggleRecordSelection(record.id!),
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}

enum ProcessName {
  hashGeneration,
  applicationSubmission,
  chainRecording,
}

enum ProcessStatus {
  pending,
  inProgress,
  completed,
  error,
}

class ProcessLog {
  final ProcessName name;
  ProcessStatus status;
  Duration? duration;
  String? errorMessage;
  String? submissionId;

  ProcessLog({
    required this.name,
    this.status = ProcessStatus.pending,
    this.duration,
    this.errorMessage,
    this.submissionId,
  });

  String get displayName {
    switch (name) {
      case ProcessName.hashGeneration:
        return '1. 生成完了';
      case ProcessName.applicationSubmission:
        return '2. データ提出';
      case ProcessName.chainRecording:
        return '3. オンチェーン記録';
    }
  }
}

class VerificationScreen extends StatefulWidget {
  final String imagePath;
  final DateTime captureTime;
  final Map<int, List<String>> hashesMap;
  final String droneId;
  final bool isHistoryView;

  const VerificationScreen({
    super.key,
    required this.imagePath,
    required this.captureTime,
    required this.hashesMap,
    required this.droneId,
    this.isHistoryView = false,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  int _selectedDuration = 30;
  final List<int> _availableDurations = [10, 20, 30, 40, 50, 60];

  late final List<ProcessLog> _processLogs;
  String? _transactionHash;

  @override
  void initState() {
    super.initState();
    _processLogs = [
      ProcessLog(
          name: ProcessName.hashGeneration, status: ProcessStatus.completed),
      ProcessLog(name: ProcessName.applicationSubmission),
      ProcessLog(name: ProcessName.chainRecording),
    ];
  }

  bool get _isProcessing =>
      _processLogs.any((log) => log.status == ProcessStatus.inProgress);
  bool get _canRecord =>
      _processLogs
          .firstWhere((log) => log.name == ProcessName.applicationSubmission)
          .status ==
      ProcessStatus.completed;

  Future<void> _submitApplication() async {
    final log = _processLogs
        .firstWhere((l) => l.name == ProcessName.applicationSubmission);
    final stopwatch = Stopwatch()..start();

    setState(() => log.status = ProcessStatus.inProgress);

    try {
      final selectedHashes = widget.hashesMap[_selectedDuration] ?? [];

      final request = http.MultipartRequest(
          'POST', Uri.parse('$SERVER_URL/submit'))
        ..files
            .add(await http.MultipartFile.fromPath('image', widget.imagePath))
        ..fields['hash'] = selectedHashes.join('\n')
        ..fields['droneId'] = widget.droneId
        ..fields['captureTime'] = widget.captureTime.toIso8601String()
        ..fields['durationSeconds'] = _selectedDuration.toString();

      final streamedResponse = await request.send();
      stopwatch.stop();
      if (!mounted) return;

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        setState(() {
          log.status = ProcessStatus.completed;
          log.duration = stopwatch.elapsed;
          log.submissionId = responseBody['submissionId'];
        });
      } else {
        throw Exception('失敗: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (stopwatch.isRunning) stopwatch.stop();
      if (!mounted) return;
      setState(() {
        log.status = ProcessStatus.error;
        log.duration = stopwatch.elapsed;
        log.errorMessage = e.toString();
      });
    }
  }

  Future<void> _recordOnChain() async {
    final log =
        _processLogs.firstWhere((l) => l.name == ProcessName.chainRecording);
    final stopwatch = Stopwatch()..start();

    setState(() {
      log.status = ProcessStatus.inProgress;
      _transactionHash = null;
    });

    try {
      final response =
          await http.post(Uri.parse('$SERVER_URL/record-on-chain'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        stopwatch.stop();
        setState(() {
          log.status = ProcessStatus.completed;
          log.duration = stopwatch.elapsed;
          _transactionHash = result['transactionHash'];
        });
      } else {
        throw Exception('失敗: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        log.status = ProcessStatus.error;
        log.duration = stopwatch.elapsed;
        log.errorMessage = e.toString();
      });
    }
  }

  void _launchUrl(String txHash) async {
    final url = Uri.parse('https://sepolia.etherscan.io/tx/$txHash');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppWebView);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        DateFormat('yyyy/MM/dd HH:mm:ss').format(widget.captureTime);

    return Scaffold(
      appBar: AppBar(title: const Text('データの確認・申請')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "撮影日時: $dateStr",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text("申請する証明期間を選択", style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _availableDurations.map((sec) {
                final isSelected = _selectedDuration == sec;
                return ChoiceChip(
                  label: Text('${sec}s'),
                  selected: isSelected,
                  onSelected: _isProcessing
                      ? null
                      : (selected) {
                          if (selected) setState(() => _selectedDuration = sec);
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            _buildActionCard(),
            const SizedBox(height: 24),
            const Text("処理ステータス",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildProcessLogList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "$_selectedDuration秒間の位置証明データを申請します",
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isProcessing ? null : _submitApplication,
              icon: const Icon(Icons.send),
              label: const Text('サーバーへ提出'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isProcessing || !_canRecord ? null : _recordOnChain,
              icon: const Icon(Icons.verified_user),
              label: const Text('ブロックチェーン記録'),
              style:
                  OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessLogList() {
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _processLogs.length,
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final log = _processLogs[index];
          return ListTile(
            leading: _getStatusIcon(log.status),
            title: Text(log.displayName),
            subtitle: _getSubtitle(log),
            trailing: log.duration != null
                ? Text("${log.duration!.inMilliseconds}ms",
                    style: const TextStyle(fontSize: 12))
                : null,
          );
        },
      ),
    );
  }

  Widget _getStatusIcon(ProcessStatus status) {
    switch (status) {
      case ProcessStatus.pending:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
      case ProcessStatus.inProgress:
        return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2));
      case ProcessStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ProcessStatus.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  Widget? _getSubtitle(ProcessLog log) {
    if (log.errorMessage != null) {
      return Text(log.errorMessage!, style: const TextStyle(color: Colors.red));
    }
    if (log.submissionId != null) {
      return Text("ID: ${log.submissionId}");
    }
    if (log.name == ProcessName.chainRecording && _transactionHash != null) {
      return InkWell(
        onTap: () => _launchUrl(_transactionHash!),
        child: Text("Tx: ${_transactionHash!.substring(0, 10)}...",
            style: const TextStyle(
                color: Colors.blue, decoration: TextDecoration.underline)),
      );
    }
    return null;
  }
}
