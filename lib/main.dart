import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();


// WorkManagerのコールバック関数（バックグラウンドで実行される）
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await _initializeNotifications();

      final prefs = await SharedPreferences.getInstance();

      // 有効かチェック
      if (!(prefs.getBool('enabled') ?? false)) {
        return Future.value(true);
      }


      // 時間帯チェック
      if (!await _isInActiveTimeRange(prefs)) {
        return Future.value(true);
      }


      // 最後の通知からの経過時間をチェック
      final lastNotificationTimeMs = prefs.getInt('lastNotificationTime') ?? 0;
      final lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(lastNotificationTimeMs);
      final now = DateTime.now();

      final snoozeMinutes = prefs.getInt('snooze') ?? 5;
      final intervalHours = prefs.getInt('hours') ?? 1;
      final intervalMinutes = prefs.getInt('minutes') ?? 0;
      final totalIntervalMinutes = intervalHours * 60 + intervalMinutes;

      // 確認済みフラグをチェック
      final confirmed = prefs.getBool('confirmed') ?? false;

      if (confirmed) {
        // 確認済みの場合、通常の間隔で通知
        if (now.difference(lastNotificationTime).inMinutes >= totalIntervalMinutes) {
          await _showNotification(prefs);
        }
      } else {
        // 未確認の場合、スヌーズ間隔で通知
        if (lastNotificationTimeMs > 0 &&
            now.difference(lastNotificationTime).inMinutes >= snoozeMinutes) {
          await _showNotification(prefs);
        } else if (lastNotificationTimeMs == 0) {
          // 初回通知
          await _showNotification(prefs);
        }
      }

      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}


Future<void> _initializeNotifications() async {
  const initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}


Future<bool> _isInActiveTimeRange(SharedPreferences prefs) async {
  final now = DateTime.now();
  final startHour = prefs.getInt('startHour') ?? 8;
  final startMinute = prefs.getInt('startMinute') ?? 0;
  final endHour = prefs.getInt('endHour') ?? 22;
  final endMinute = prefs.getInt('endMinute') ?? 0;


  final currentMinutes = now.hour * 60 + now.minute;
  final startMinutes = startHour * 60 + startMinute;
  final endMinutes = endHour * 60 + endMinute;


  return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
}


Future<void> _showNotification(SharedPreferences prefs) async {
  final title = prefs.getString('title') ?? 'リマインダー';
  final message = prefs.getString('message') ?? '確認してください';


  const androidDetails = AndroidNotificationDetails(
    'reminder_channel',
    'リマインダー',
    channelDescription: '定期的なリマインダー通知',
    importance: Importance.high,
    priority: Priority.high,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'confirm',
        '確認',
        showsUserInterface: true,
      ),
    ],
  );


  const notificationDetails = NotificationDetails(android: androidDetails);


  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    message,
    notificationDetails,
    payload: 'reminder',
  );


  // 通知時刻を保存
  await prefs.setInt('lastNotificationTime', DateTime.now().millisecondsSinceEpoch);
  await prefs.setBool('confirmed', false);
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // WorkManager初期化
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // 通知初期化
  const initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (details) async {
      if (details.actionId == 'confirm') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('confirmed', true);
        await prefs.setInt('lastNotificationTime', DateTime.now().millisecondsSinceEpoch);
        await flutterLocalNotificationsPlugin.cancel(0);
      }
    },
  );

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'リマインダーアプリ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ReminderScreen(),
    );
  }
}


class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});


  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}


class _ReminderScreenState extends State<ReminderScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _hoursController = TextEditingController(text: '1');
  final _minutesController = TextEditingController(text: '0');
  final _snoozeMinutesController = TextEditingController(text: '5');

  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);
  bool _isEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }


  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _titleController.text = prefs.getString('title') ?? 'リマインダー';
      _messageController.text = prefs.getString('message') ?? '確認してください';
      _hoursController.text = prefs.getInt('hours')?.toString() ?? '1';
      _minutesController.text = prefs.getInt('minutes')?.toString() ?? '0';
      _snoozeMinutesController.text = prefs.getInt('snooze')?.toString() ?? '5';
      _isEnabled = prefs.getBool('enabled') ?? false;

      int startHour = prefs.getInt('startHour') ?? 8;
      int startMinute = prefs.getInt('startMinute') ?? 0;
      _startTime = TimeOfDay(hour: startHour, minute: startMinute);

      int endHour = prefs.getInt('endHour') ?? 22;
      int endMinute = prefs.getInt('endMinute') ?? 0;
      _endTime = TimeOfDay(hour: endHour, minute: endMinute);
    });
  }


  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('title', _titleController.text);
    await prefs.setString('message', _messageController.text);
    await prefs.setInt('hours', int.tryParse(_hoursController.text) ?? 1);
    await prefs.setInt('minutes', int.tryParse(_minutesController.text) ?? 0);
    await prefs.setInt('snooze', int.tryParse(_snoozeMinutesController.text) ?? 5);
    await prefs.setBool('enabled', _isEnabled);
    await prefs.setInt('startHour', _startTime.hour);
    await prefs.setInt('startMinute', _startTime.minute);
    await prefs.setInt('endHour', _endTime.hour);
    await prefs.setInt('endMinute', _endTime.minute);
  }


  Future<void> _toggleEnabled() async {
    if (!_isEnabled) {
      // 通知権限をリクエスト
      var status = await Permission.notification.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('通知の許可が必要です')),
          );
        }
        return;
      }
    }

    setState(() {
      _isEnabled = !_isEnabled;
    });

    await _saveSettings();

    if (_isEnabled) {
      // WorkManagerタスクを登録（1分ごとにチェック）
      await Workmanager().registerPeriodicTask(
        'reminder-task',
        'reminderTask',
        frequency: const Duration(minutes: 15), // 最小15分
        initialDelay: const Duration(seconds: 10),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      // 即座にチェック用の1回限りタスクも登録
      await Workmanager().registerOneOffTask(
        'reminder-check',
        'reminderTask',
        initialDelay: const Duration(seconds: 5),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リマインダーを開始しました\n（バックグラウンドで動作します）')),
        );
      }
    } else {
      // WorkManagerタスクをキャンセル
      await Workmanager().cancelByUniqueName('reminder-task');
      await Workmanager().cancelByUniqueName('reminder-check');
      await flutterLocalNotificationsPlugin.cancel(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リマインダーを停止しました')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('リマインダー設定'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '動作状態',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: _isEnabled,
                          onChanged: (_) => _toggleEnabled(),
                        ),
                      ],
                    ),
                    if (_isEnabled)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '✓ バックグラウンドで動作中',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('通知内容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'メッセージ',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 24),
            const Text('通知間隔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hoursController,
                    decoration: const InputDecoration(
                      labelText: '時間',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _saveSettings(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minutesController,
                    decoration: const InputDecoration(
                      labelText: '分',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _saveSettings(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('再通知までの時間', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _snoozeMinutesController,
              decoration: const InputDecoration(
                labelText: '分',
                border: OutlineInputBorder(),
                helperText: '無視した場合の再通知間隔',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 24),
            const Text('通知時間帯', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('開始時刻'),
                        TextButton(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _startTime,
                            );
                            if (time != null) {
                              setState(() {
                                _startTime = time;
                              });
                              _saveSettings();
                            }
                          },
                          child: Text(
                            '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('終了時刻'),
                        TextButton(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _endTime,
                            );
                            if (time != null) {
                              setState(() {
                                _endTime = time;
                              });
                              _saveSettings();
                            }
                          },
                          child: Text(
                            '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'アプリを閉じても通知は継続されます',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}