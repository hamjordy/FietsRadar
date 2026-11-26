import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'services/shared_report_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedReportService.initialize();
  runApp(const FietsRadarApp());
}
