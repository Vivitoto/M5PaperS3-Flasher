import 'package:flutter/material.dart';

import 'firmware_list_screen.dart';
import 'local_firmware_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [
    FirmwareListScreen(),
    LocalFirmwareScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: NavigationBar(
              height: 60,
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.developer_board_outlined),
                  selectedIcon: Icon(Icons.developer_board),
                  label: '固件',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_copy_outlined),
                  selectedIcon: Icon(Icons.folder_copy),
                  label: '本地/烧录',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
