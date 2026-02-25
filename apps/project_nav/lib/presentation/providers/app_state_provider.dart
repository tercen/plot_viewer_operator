import 'package:flutter/material.dart';
import '../../di/service_locator.dart';
import '../../domain/models/tree_node.dart';
import '../../domain/services/data_service.dart';
import '../../utils/message_helper.dart';

/// State provider for the project navigator tree.
///
/// Manages: project loading, lazy child loading, expand/collapse,
/// search filtering, and data step selection.
class AppStateProvider extends ChangeNotifier {
  final DataService _dataService;

  AppStateProvider({DataService? dataService})
      : _dataService = dataService ?? serviceLocator<DataService>();

  // --- Data loading state ---
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  // --- Tree data ---
  List<TreeNode> _projects = [];
  List<TreeNode> get projects => _projects;

  // Children keyed by parent node ID
  final Map<String, List<TreeNode>> _children = {};
  List<TreeNode> childrenOf(String nodeId) => _children[nodeId] ?? [];

  // Node IDs currently loading their children
  final Set<String> _loadingNodes = {};
  bool isNodeLoading(String nodeId) => _loadingNodes.contains(nodeId);

  // --- Expand/collapse state ---
  final Set<String> _expandedNodes = {};
  bool isExpanded(String nodeId) => _expandedNodes.contains(nodeId);

  // Saved expand state before search, for restore on clear
  Set<String>? _preSearchExpandState;

  // --- Selection ---
  String? _selectedStepId;
  String? get selectedStepId => _selectedStepId;

  // --- Search ---
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  /// Load root projects on startup.
  Future<void> loadData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _projects = await _dataService.loadProjects();
    } catch (e) {
      _error = 'Failed to load projects: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Toggle expand/collapse for a node. On first expand, lazy-loads children.
  Future<void> toggleExpand(String nodeId, TreeNodeType nodeType) async {
    if (_expandedNodes.contains(nodeId)) {
      _expandedNodes.remove(nodeId);
      notifyListeners();
      return;
    }

    _expandedNodes.add(nodeId);

    // Lazy-load children if not yet loaded
    if (!_children.containsKey(nodeId)) {
      _loadingNodes.add(nodeId);
      notifyListeners();

      try {
        final children = switch (nodeType) {
          TreeNodeType.project => await _dataService.loadWorkflows(nodeId),
          TreeNodeType.workflow => await _dataService.loadDataSteps(nodeId),
          TreeNodeType.dataStep => <TreeNode>[],
        };
        _children[nodeId] = children;
      } catch (e) {
        _error = 'Failed to load children: $e';
        _expandedNodes.remove(nodeId);
      }
      _loadingNodes.remove(nodeId);
    }

    notifyListeners();
  }

  /// Select a data step and broadcast step-selected message.
  void selectStep(TreeNode step) {
    _selectedStepId = step.id;
    notifyListeners();

    // Find ancestor IDs from the tree structure
    final workflowId = step.parentId;
    String? projectId;
    if (workflowId != null) {
      for (final entry in _children.entries) {
        if (entry.value.any((n) => n.id == workflowId)) {
          projectId = entry.key;
          break;
        }
      }
    }

    // Broadcast step-selected to all apps
    MessageHelper.postMessage(
      'step-selected',
      {
        'projectId': projectId ?? '',
        'workflowId': workflowId ?? '',
        'stepId': step.id,
      },
      target: '*',
    );
  }

  /// Set search query and filter the tree.
  void setSearchQuery(String value) {
    if (value.isNotEmpty && _searchQuery.isEmpty) {
      // Entering search mode — save expand state
      _preSearchExpandState = Set<String>.from(_expandedNodes);
    }

    _searchQuery = value;

    if (value.isEmpty && _preSearchExpandState != null) {
      // Leaving search mode — restore expand state
      _expandedNodes
        ..clear()
        ..addAll(_preSearchExpandState!);
      _preSearchExpandState = null;
    } else if (value.isNotEmpty) {
      // Auto-expand ancestors of matching nodes
      _autoExpandForSearch();
    }

    notifyListeners();
  }

  /// Check if a node matches the current search query.
  bool nodeMatchesSearch(TreeNode node) {
    if (_searchQuery.isEmpty) return true;
    return node.name.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  /// Check if a node or any of its loaded descendants match the search query.
  bool nodeOrDescendantsMatch(TreeNode node) {
    if (_searchQuery.isEmpty) return true;
    if (nodeMatchesSearch(node)) return true;

    final children = _children[node.id];
    if (children == null) return false;

    for (final child in children) {
      if (nodeMatchesSearch(child)) return true;
      final grandchildren = _children[child.id];
      if (grandchildren != null) {
        for (final gc in grandchildren) {
          if (nodeMatchesSearch(gc)) return true;
        }
      }
    }
    return false;
  }

  /// Get filtered projects based on search query.
  List<TreeNode> get filteredProjects {
    if (_searchQuery.isEmpty) return _projects;
    return _projects.where((p) => nodeOrDescendantsMatch(p)).toList();
  }

  /// Get filtered children of a node based on search query.
  List<TreeNode> filteredChildrenOf(String nodeId) {
    final children = _children[nodeId] ?? [];
    if (_searchQuery.isEmpty) return children;
    return children.where((c) => nodeOrDescendantsMatch(c)).toList();
  }

  /// Auto-expand ancestor nodes of search matches.
  void _autoExpandForSearch() {
    for (final project in _projects) {
      if (nodeOrDescendantsMatch(project) && _children.containsKey(project.id)) {
        _expandedNodes.add(project.id);

        final workflows = _children[project.id] ?? [];
        for (final wf in workflows) {
          if (nodeOrDescendantsMatch(wf) && _children.containsKey(wf.id)) {
            _expandedNodes.add(wf.id);
          }
        }
      }
    }
  }
}
