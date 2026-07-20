/// SAFEBOAT — Âncora Virtual (app Flutter).
///
/// Roda em modo DEMO com o dispositivo simulado (paridade total com o protótipo
/// web e com os testes). Para conectar o SAFEBOAT real, ver AnchorController
/// .connectDevice() + SafeboatAdapter.
import 'package:flutter/material.dart';

import 'features/anchor/screens/anchor_screen.dart';
import 'theme.dart';

void main() => runApp(const SafeboatAncoraApp());

class SafeboatAncoraApp extends StatelessWidget {
  const SafeboatAncoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAFEBOAT — Âncora Virtual',
      debugShowCheckedModeBanner: false,
      theme: SB.theme(),
      home: const AnchorScreen(),
    );
  }
}
