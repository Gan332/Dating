import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'models/app_settings.dart';
import 'ui/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // release 包里异常默认只进 logcat，这里再打一份，方便定位启动问题。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('未捕获的界面异常：${details.exceptionAsString()}');
  };
  runApp(const DaymarkApp());
}

class DaymarkApp extends StatefulWidget {
  const DaymarkApp({super.key});

  @override
  State<DaymarkApp> createState() => _DaymarkAppState();
}

class _DaymarkAppState extends State<DaymarkApp> {
  late final AppController _controller;

  /// 手动切换深浅色用的控制器，跟随系统时不会用到。
  late final M3EThemeController _themeController = M3EThemeController();

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    // load() 内部会兜住超时与异常，不会把启动流程挂住。
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _themeController.dispose();
    super.dispose();
  }

  void _retry() => _controller.reload();

  @override
  Widget build(BuildContext context) {
    return M3EMaterialApp(
      title: '拾日',
      debugShowCheckedModeBanner: false,
      data: M3EThemeData.light(
        seedColor: Color(AppSeed.purple.colorValue),
      ),
      autoTheming: true,
      dynamicColoring: false,
      drawUnderSystemBars: false,
      fontFamily: 'sans-serif',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final settings = _controller.settings;
          return M3EThemeScope(
            baseData: M3EThemeData.light(
              seedColor: Color(settings.seed.colorValue),
            ),
            controller: _themeController,
            autoTheming: settings.themeMode == AppThemeMode.system,
            initialTheme: settings.themeMode == AppThemeMode.dark
                ? Brightness.dark
                : Brightness.light,
            dynamicColoring: settings.useDynamicColor,
            child: _controller.ready
                ? AppShell(controller: _controller, onRetry: _retry)
                : const _StartupView(),
          );
        },
      ),
    );
  }
}

class _StartupView extends StatelessWidget {
  const _StartupView();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3ELoadingIndicator(size: 42),
              SizedBox(height: 18),
              Text('正在准备本地数据…'),
            ],
          ),
        ),
      );
}
