import '../models/factor.dart';

/// Service interface for loading factor data.
///
/// Phase 3: Real implementation querying Tercen API via sci_tercen_client.
abstract class DataService {
  /// Load all available factors for the given step within a workflow.
  Future<List<Factor>> loadFactors(String workflowId, String stepId);
}
