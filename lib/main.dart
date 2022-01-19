import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator/background_locator.dart';
import 'package:background_locator/location_dto.dart';
import 'package:background_locator/settings/android_settings.dart';
import 'package:background_locator/settings/ios_settings.dart';
import 'package:background_locator/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:location_permissions/location_permissions.dart';

import 'file_manager.dart';
import 'location_callback_handler.dart';
import 'location_service_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(App());

class App extends StatefulWidget {
  const App({Key key}) : super(key: key);

  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> with SingleTickerProviderStateMixin {
  AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyApp(),
    );
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  ReceivePort port = ReceivePort();
  ReceivePort portDistance = ReceivePort();

  String logStr = '';
  bool isRunning;
  LocationDto lastLocation;
  int time = 0;
  Timer timer = null;
  double distance = 0.0;

  @override
  void initState() {
    super.initState();

    if (IsolateNameServer.lookupPortByName(LocationServiceRepository.isolateName) != null) {
      IsolateNameServer.removePortNameMapping(LocationServiceRepository.isolateName);
    }
    if (IsolateNameServer.lookupPortByName(LocationServiceRepository.isolateDistanceName) != null) {
      IsolateNameServer.removePortNameMapping(LocationServiceRepository.isolateDistanceName);
    }

    IsolateNameServer.registerPortWithName(port.sendPort, LocationServiceRepository.isolateName);
    IsolateNameServer.registerPortWithName(portDistance.sendPort, LocationServiceRepository.isolateDistanceName);

    port.listen(
      (dynamic data) async {
        await updateUI(data);
      },
    );

    portDistance.listen(
      (dynamic data) async {
        setState(() {
          distance = data;
        });
      },
    );

    initPlatformState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> updateUI(LocationDto data) async {
    final log = await FileManager.readLogFile();

    await _updateNotificationText(data);

    setState(() {
      if (data != null) {
        lastLocation = data;
      }
      logStr = log;
    });
  }

  Future<void> _updateNotificationText(LocationDto data) async {
    if (data == null) {
      return;
    }

    await BackgroundLocator.updateNotificationText(title: "new location received", msg: "${DateTime.now()}", bigMsg: "${data.latitude}, ${data.longitude}");
  }

  Future<void> initPlatformState() async {
    print('Initializing...');
    await BackgroundLocator.initialize();
    logStr = await FileManager.readLogFile();
    print('Initialization done');

    final _isRunning = await BackgroundLocator.isServiceRunning();
    setState(() {
      isRunning = _isRunning;
    });
    if (isRunning != null && isRunning) {
      _starTimer();
    } else {
      final SharedPreferences prefs = await _prefs;
      prefs.setInt('timeStamp', 0);
    }
    print('Running ${isRunning.toString()}');
  }

  @override
  Widget build(BuildContext context) {
    final start = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Start'),
        onPressed: (isRunning != null && isRunning)
            ? null
            : () {
                _onStart();
              },
      ),
    );
    final stop = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Stop'),
        onPressed: (isRunning != null && isRunning)
            ? () {
                onStop();
              }
            : null,
      ),
    );
    final clear = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Clear Log'),
        onPressed: () {
          FileManager.clearLogFile();
          setState(() {
            logStr = '';
          });
        },
      ),
    );

    Widget timebox;
    if (isRunning != null && isRunning) {
      timebox = SizedBox(
        width: double.maxFinite,
        child: ElevatedButton(
          child: Text(Duration(seconds: time).toString().split('.').first.padLeft(8, "0") + " Time"),
          onPressed: () {},
        ),
      );
    } else {
      timebox = Container();
    }

    Widget distancebox;
    if (isRunning != null && isRunning) {
      distancebox = SizedBox(
        width: double.maxFinite,
        child: ElevatedButton(
          child: Text(distance.toStringAsFixed(2) + " Mile"),
          onPressed: () {},
        ),
      );
    } else {
      distancebox = Container();
    }

    String msgStatus = "-";
    if (isRunning != null) {
      if (isRunning) {
        msgStatus = 'Is running';
      } else {
        msgStatus = 'Is not running';
      }
    }
    final status = Text("Status: $msgStatus");

    final log = Text(
      logStr,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Running Tracker'),
      ),
      body: Container(
        width: double.maxFinite,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[start, stop, timebox, distancebox],
          ),
        ),
      ),
    );
  }

  void onStop() async {
    if (timer != null) {
      timer.cancel();
      timer = null;
    }
    final SharedPreferences prefs = await _prefs;
    prefs.setInt('timeStamp', 0);
    prefs.setDouble('last_lat', 0.0);
    prefs.setDouble('last_lon', 0.0);
    distance = 0.0;
    await BackgroundLocator.unRegisterLocationUpdate();
    final _isRunning = await BackgroundLocator.isServiceRunning();
    setState(() {
      isRunning = _isRunning;
    });
  }

  void _onStart() async {
    if (await _checkLocationPermission()) {
      print("with permissoion");
      await _startLocator();
      final _isRunning = await BackgroundLocator.isServiceRunning();
      _starTimer();

      setState(() {
        isRunning = _isRunning;
        lastLocation = null;
      });
    } else {
      print("no permissoion");
      _showDialog(context);
    }
  }

  void _starTimer() async {
    if (timer != null) {
      timer.cancel();
      timer = null;
    }
    final SharedPreferences prefs = await _prefs;
    int timeStamp = prefs.getInt('timeStamp') ?? 0;
    int currentTimeStamp = DateTime.now().millisecondsSinceEpoch;
    if (timeStamp == 0) {
      prefs.setInt('timeStamp', currentTimeStamp);
      time = 0;
    } else {
      time = ((currentTimeStamp - timeStamp) / 1000).round();
    }
    Timer.periodic(Duration(seconds: 1), (timer) async {
      this.timer = timer;
      setState(() {
        time = time + 1;
      });
    });
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Alert"),
          content: Text("Please enable location permisson from setting page to continue tracking app."),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> _checkLocationPermission() async {
    final access = await LocationPermissions().checkPermissionStatus();
    switch (access) {
      case PermissionStatus.unknown:
      case PermissionStatus.denied:
      case PermissionStatus.restricted:
        final permission = await LocationPermissions().requestPermissions(
          permissionLevel: LocationPermissionLevel.locationAlways,
        );
        if (permission == PermissionStatus.granted) {
          return true;
        } else {
          return false;
        }
        break;
      case PermissionStatus.granted:
        return true;
        break;
      default:
        return false;
        break;
    }
  }

  Future<void> _startLocator() async {
    Map<String, dynamic> data = {'countInit': 1};
    return await BackgroundLocator.registerLocationUpdate(LocationCallbackHandler.callback,
        initCallback: LocationCallbackHandler.initCallback,
        initDataCallback: data,
        disposeCallback: LocationCallbackHandler.disposeCallback,
        iosSettings: IOSSettings(accuracy: LocationAccuracy.NAVIGATION, distanceFilter: 5),
        autoStop: false,
        androidSettings: AndroidSettings(
            accuracy: LocationAccuracy.NAVIGATION,
            interval: 5,
            distanceFilter: 5,
            client: LocationClient.google,
            androidNotificationSettings: AndroidNotificationSettings(
                notificationChannelName: 'Location tracking',
                notificationTitle: 'Start Location Tracking',
                notificationMsg: 'Track location in background',
                notificationBigMsg: 'Background location is on to keep the app up-tp-date with your location. This is required for main features to work properly when the app is not running.',
                notificationIconColor: Colors.grey,
                notificationTapCallback: LocationCallbackHandler.notificationCallback)));
  }
}
