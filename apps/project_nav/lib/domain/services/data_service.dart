import '../models/tree_node.dart';

/// Service interface for loading project tree data.
///
/// Phase 2: Mock implementation with hardcoded data.
/// Phase 3: Real implementation querying Tercen API.
abstract class DataService {
  /// Load all root-level projects for the authenticated user.
  Future<List<TreeNode>> loadProjects();

  /// Load workflows for a given project.
  Future<List<TreeNode>> loadWorkflows(String projectId);

  /// Load data steps for a given workflow.
  Future<List<TreeNode>> loadDataSteps(String workflowId);
}
