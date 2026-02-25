import 'package:widget_library/widget_library.dart';

/// Service interface for loading factor data.
abstract class DataService {
  /// Load all available factors for the given step within a workflow.
  Future<List<Factor>> loadFactors(String workflowId, String stepId);
}
