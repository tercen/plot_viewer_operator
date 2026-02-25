/// Types of nodes in the project tree hierarchy.
enum TreeNodeType { project, workflow, dataStep }

/// A node in the project navigation tree.
///
/// Represents a project, workflow, or data step. Projects contain workflows,
/// workflows contain data steps. Data steps are leaf nodes.
class TreeNode {
  final String id;
  final String name;
  final TreeNodeType type;
  final String? parentId;

  const TreeNode({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
  });

  bool get isLeaf => type == TreeNodeType.dataStep;
  bool get isExpandable => !isLeaf;
}
