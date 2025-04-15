import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(home: BleApp()));
}

class BleApp extends StatefulWidget {
  const BleApp({super.key});
  @override
  State<BleApp> createState() => _BleAppState();
}

class _BleAppState extends State<BleApp> {
  List<ScanResult> devices = [];
  BluetoothDevice? connectedDevice;
  String temperatureText = '';
  String motionText = '';
  final VolumeController _volumeController = VolumeController.instance;
  double _timeValue = 20;
  bool _isMuted = false;
  bool _active = false;
  BluetoothCharacteristic? _timeCharacteristic;

  @override
  void initState() {
    super.initState();
    startScan();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool isMuted = await _volumeController.isMuted();
      setState(() => _isMuted = isMuted);
      await _startBackground();
    });
  }

  void _sleep() async {
    if (connectedDevice != null) {
      try {
        await ScreenBrightness.instance.setSystemScreenBrightness(0.01);
        await updateMuteStatus(true);
        setState(() {});
        _active = true;
      } catch (e) {
        debugPrint(e.toString());
        throw 'Failed to sleep';
      }
    }
  }

  void _wakeup() async {
    if (connectedDevice != null) {
      try {
        await ScreenBrightness.instance.setSystemScreenBrightness(0.4);
        await updateMuteStatus(false);
        setState(() {});
        _active = false;
      } catch (e) {
        debugPrint(e.toString());
        throw 'Failed to wake up';
      }
    }
  }

  Future<bool> _hasAllPermissions() async {
    final location = await Permission.locationAlways.status;
    final bluetooth = await Permission.bluetooth.status;

    return location.isGranted && bluetooth.isGranted;
  }

  Future<void> _startBackground() async {
    final hasPermissions = await _hasAllPermissions();
    if (!hasPermissions) {
      return;
    }

    final androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "BLE Monitoring",
      notificationText: "Monitoring BLE device in the background",
      notificationIcon: AndroidResource(
        name: 'background_icon',
        defType: 'drawable',
      ),
    );

    final success = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );

    if (success) {
      await FlutterBackground.enableBackgroundExecution();
      if (kDebugMode) {
        print("fonul este activat");
      }
    } else {
      if (kDebugMode) {
        print("nu sa primit ");
      }
    }
  }

  void startScan() async {
    if (Platform.isAndroid) {
      var status = await Permission.bluetoothScan.request();
      var status2 = await Permission.bluetoothConnect.request();
      var statusLocation = await Permission.location.request();
      if (status.isGranted && status2.isGranted && statusLocation.isGranted) {
        devices.clear();
        setState(() {});
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        FlutterBluePlus.scanResults.listen((results) {
          setState(() {
            devices =
                results.where((r) => r.device.advName.isNotEmpty).toList();
          });
        });
      } else {
        if (kDebugMode) {
          print('Bluetooth permissions denied');
        }
      }
    } else {
      devices.clear();
      setState(() {});
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          devices = results.where((r) => r.device.advName.isNotEmpty).toList();
        });
      });
    }
  }

  void sendSliderData(double value) async {
    if (connectedDevice != null && _timeCharacteristic != null) {
      try {
        final valueToSend = utf8.encode(value.toString());
        await _timeCharacteristic?.write(valueToSend, withoutResponse: true);
      } catch (e) {
        if (kDebugMode) {
          print("Eroare la trimiterea timpului: $e");
        }
      }
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    await device.connect();
    connectedDevice = device;
    final services = await device.discoverServices();

    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.properties.notify) {
          await char.setNotifyValue(true);
          char.lastValueStream.listen((value) {
            final text = _decode(value);
            setState(() {
              if (text.contains("C") || text.contains("F")) {
                temperatureText = text;
              } else if (text.contains("miscari")) {
                _sleep();
                motionText = text;
              } else if (text.contains("actiune")) {
                _wakeup();
                motionText = text;
              }
            });
          });
        }

        if (char.uuid.toString() == '00000005-710e-4a5b-8d75-3e5b444bc3cf') {
          _timeCharacteristic = char;
        }
      }
    }

    setState(() {});
  }

  String _decode(List<int> value) {
    try {
      return utf8.decode(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          connectedDevice == null
              ? 'Bluetooth devices:'
              : 'Connected: ${connectedDevice!.advName}',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body:
          connectedDevice == null
              ? ListView(
                children:
                    devices.map((r) {
                      return ListTile(
                        title: Text(r.device.advName),
                        subtitle: Text(r.device.remoteId.toString()),
                        onTap: () => connectToDevice(r.device),
                      );
                    }).toList(),
              )
              : Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(
                          "🌡 Temperatura raspberry pi: $temperatureText",
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "🚨 Statutul: $motionText",
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          "Acum:",
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          _active && _isMuted ? 'Dormim' : 'Activam',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _sleep,
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.all<Color>(
                                  _active && _isMuted
                                      ? const Color.fromARGB(255, 112, 77, 119)
                                      : const Color.fromARGB(
                                        255,
                                        255,
                                        255,
                                        255,
                                      ),
                                ),
                                foregroundColor: WidgetStateProperty.all<Color>(
                                  const Color.fromARGB(255, 165, 155, 155),
                                ),
                              ),
                              child: Text('Sleep'),
                            ),
                            TextButton(
                              onPressed: _wakeup,
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.all<Color>(
                                  _active && _isMuted
                                      ? const Color.fromARGB(255, 255, 255, 255)
                                      : const Color.fromARGB(255, 112, 77, 119),
                                ),
                                foregroundColor: WidgetStateProperty.all<Color>(
                                  const Color.fromARGB(255, 165, 155, 155),
                                ),
                              ),
                              child: Text('Wake up'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent[100],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.all(26),
                          margin: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Text(
                                'Timpul de inactiune',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Slider(
                                value: _timeValue,
                                max: 100,
                                divisions: 20,
                                label: _timeValue.round().toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _timeValue = value;
                                  });
                                  sendSliderData(value);
                                },
                              ),
                              Text(
                                ' ${_timeValue.round()} secunde',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: () {
                            connectedDevice?.disconnect();
                            setState(() {
                              connectedDevice = null;
                              temperatureText = '';
                              motionText = '';
                            });
                          },
                          child: const Text("Deconectare"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      floatingActionButton:
          connectedDevice == null
              ? FloatingActionButton(
                onPressed: startScan,
                child: const Icon(Icons.refresh),
              )
              : null,
    );
  }

  Future<void> updateMuteStatus(bool isMute) async {
    await _volumeController.setMute(isMute);
    if (Platform.isIOS) {
      await Future.delayed(Duration(milliseconds: 50));
    }
    _isMuted = await _volumeController.isMuted();

    setState(() {});
  }
}
