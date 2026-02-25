import 'package:flutter/foundation.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart'
    show ServiceFactory;

import '../../domain/models/tree_node.dart';
import '../../domain/services/data_service.dart';

/// Real Tercen implementation of DataService using entity services (Flow D).
///
/// Uses stream extension methods for paginated range queries,
/// and fetches full Workflow objects to extract their data steps.
class TercenDataService implements DataService {
  final ServiceFactory _factory;
  final String _teamId;

  TercenDataService(this._factory, {required String teamId})
      : _teamId = teamId;

  @override
  Future<List<TreeNode>> loadProjects() async {
    debugPrint('TercenDataService.loadProjects: teamId=$_teamId');

    final projects = await (_factory.projectService as sci.ProjectService)
        .findByTeamAndIsPublicAndLastModifiedDateStream(
          startKeyOwner: _teamId,
          endKeyOwner: _teamId,
        )
        .toList();

    return projects
        .map((p) => TreeNode(
              id: p.id,
              name: p.name,
              type: TreeNodeType.project,
            ))
        .toList();
  }

  @override
  Future<List<TreeNode>> loadWorkflows(String projectId) async {
    debugPrint('TercenDataService.loadWorkflows: projectId=$projectId');

    final docs =
        await (_factory.projectDocumentService as sci.ProjectDocumentService)
            .findProjectObjectsByFolderAndNameStream(
              startKeyProjectId: projectId,
              endKeyProjectId: projectId,
              useFactory: true,
            )
            .toList();

    return docs
        .whereType<sci.Workflow>()
        .map((w) => TreeNode(
              id: w.id,
              name: w.name,
              type: TreeNodeType.workflow,
              parentId: projectId,
            ))
        .toList();
  }

  @override
  Future<List<TreeNode>> loadDataSteps(String workflowId) async {
    debugPrint('TercenDataService.loadDataSteps: workflowId=$workflowId');

    final workflow = await _factory.workflowService.get(workflowId);

    return workflow.steps
        .whereType<sci.DataStep>()
        .map((step) => TreeNode(
              id: step.id,
              name: step.name,
              type: TreeNodeType.dataStep,
              parentId: workflowId,
            ))
        .toList();
  }
}
