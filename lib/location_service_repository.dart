import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:background_locator/location_dto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_manager.dart';

class LocationServiceRepository {
  static LocationServiceRepository _instance = LocationServiceRepository._();

  LocationServiceRepository._();

  factory LocationServiceRepository() {
    return _instance;
  }

  static const String isolateName = 'LocatorIsolate';
  static const String isolateDistanceName = 'LocatorDistanceIsolate';

  int _count = -1;
  double distance = 0.0;

  Future<void> init(Map<dynamic, dynamic> params) async {
    //TODO change logs
    print("***********Init callback handler");
    if (params.containsKey('countInit')) {
      dynamic tmpCount = params['countInit'];
      if (tmpCount is double) {
        _count = tmpCount.toInt();
      } else if (tmpCount is String) {
        _count = int.parse(tmpCount);
      } else if (tmpCount is int) {
        _count = tmpCount;
      } else {
        _count = -2;
      }
    } else {
      _count = 0;
    }
    print("$_count");
    await setLogLabel("start");
    final SendPort send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(null);
  }

  Future<void> dispose() async {
    distance = 0.0;
    print("***********Dispose callback handler");
    print("$_count");
    await setLogLabel("end");
    final SendPort send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(null);
  }

  Future<void> callback(LocationDto locationDto) async {
    final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
    final SharedPreferences prefs = await _prefs;
    double lastLat = prefs.getDouble('last_lat') ?? 0.0;
    double lastLong = prefs.getDouble('last_lon') ?? 0.0;
    if (lastLat != 0.0 && lastLong != 0.0) {
      double newDistance = calculateDistance(lastLat, lastLong, locationDto.latitude, locationDto.longitude);
      distance = distance + newDistance;
      print("vishal-$_count->{$lastLat}->{$lastLong}");
      print("vishal-$_count->{${locationDto.latitude}}->{${locationDto.longitude}}");
      print("vishal-$_count->{$distance}");      
    }
    prefs.setDouble('last_lat', locationDto.latitude);
    prefs.setDouble('last_lon', locationDto.longitude);
    await setLogPosition(_count, locationDto);
    final SendPort send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(locationDto);
    final SendPort distancePort = IsolateNameServer.lookupPortByName(isolateDistanceName);
    distancePort?.send(distance);
    _count++;
  }

  static Future<void> setLogLabel(String label) async {
    final date = DateTime.now();
    await FileManager.writeToLogFile('------------\n$label: ${formatDateLog(date)}\n------------\n');
  }

  static Future<void> setLogPosition(int count, LocationDto data) async {
    final date = DateTime.now();
    await FileManager.writeToLogFile('$count : ${formatDateLog(date)} --> ${formatLog(data)} --- isMocked: ${data.isMocked}\n');
  }

  static double dp(double val, int places) {
    double mod = pow(10.0, places);
    return ((val * mod).round().toDouble() / mod);
  }

  static String formatDateLog(DateTime date) {
    return date.hour.toString() + ":" + date.minute.toString() + ":" + date.second.toString();
  }

  static String formatLog(LocationDto locationDto) {
    return dp(locationDto.latitude, 4).toString() + " " + dp(locationDto.longitude, 4).toString();
  }

  static double calculateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    var km= 12742 * asin(sqrt(a));
    var mile = km/1.609344;
    return mile;
  }
}
