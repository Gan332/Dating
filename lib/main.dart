import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'ui/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DaymarkApp());
}

class DaymarkApp extends StatefulWidget {
  const DaymarkApp({super.key});

  @override
  State<DaymarkApp> createState() => _DaymarkAppState();
}

class _DaymarkAppState extends State<DaymarkApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return M3EMaterialApp(
      title: '拾日',
      debugShowCheckedModeBanner: false,
      data: M3EThemeData.light(seedColor: const Color(0xFF6750A4)),
      fontFamily: 'sans-serif',
      autoTheming: true,
      dynamicColoring: false,
      drawUnderSystemBars: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.ready) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppShell(controller: _controller);
        },
      ),
    );
  }
}
