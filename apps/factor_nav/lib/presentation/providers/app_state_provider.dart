import 'package:flutter/material.dart';
import '../../di/service_locator.dart';
import '../../domain/models/factor.dart';
import '../../domain/services/data_service.dart';

/// State provider for the factor navigator.
///
/// Manages: factor loading, search filtering, namespace expand/collapse.
/// Wiring: control.onChanged -> provider.setXxx() -> notifyListeners() -> Consumer rebuilds
class AppStateProvider extends ChangeNotifier {
  final DataService _dataService;

  AppStateProvider({DataService? dataService})
      : _dataService = dataService ?? serviceLocator<DataService>();

  // --- Data loading state ---
  bool _isLoading = false;
  String? _error;
  bool _hasStep = false;
  String? _workflowId;
  String? _stepId;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasStep => _hasStep;
  String? get workflowId => _workflowId;
  String? get stepId => _stepId;

  // --- Raw factor data ---
  List<Factor> _factors = [];

  // --- Search ---
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // --- Expand/collapse ---
  final Set<String> _expandedNamespaces = {};
  bool isNamespaceExpanded(String namespace) =>
      _expandedNamespaces.contains(namespace);

  /// All unique namespaces from the loaded factors, sorted alphabetically.
  /// Factors without a dot in their name are grouped under an empty string key.
  List<String> get namespaces {
    final ns = _factors
        .map((f) => f.namespace)
        .toSet()
        .toList()
      ..sort();
    return ns;
  }

  /// Factors grouped by namespace, each group sorted alphabetically by shortName.
  /// Factors without a namespace are grouped under the empty string key.
  Map<String, List<Factor>> get groupedFactors {
    final map = <String, List<Factor>>{};
    for (final ns in namespaces) {
      final factors = _factors.where((f) => f.namespace == ns).toList()
        ..sort((a, b) => a.shortName.compareTo(b.shortName));
      map[ns] = factors;
    }
    return map;
  }

  /// Filtered grouped factors based on search query.
  /// Only includes namespace groups that have matching factors.
  Map<String, List<Factor>> get filteredGroupedFactors {
    if (_searchQuery.isEmpty) return groupedFactors;

    final query = _searchQuery.toLowerCase();
    final map = <String, List<Factor>>{};
    for (final entry in groupedFactors.entries) {
      final matching = entry.value
          .where((f) => f.name.toLowerCase().contains(query))
          .toList();
      if (matching.isNotEmpty) {
        map[entry.key] = matching;
      }
    }
    return map;
  }

  /// Total number of factors (unfiltered).
  int get factorCount => _factors.length;

  /// Load factors for a step within a workflow.
  Future<void> loadFactors(String workflowId, String stepId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _factors = await _dataService.loadFactors(workflowId, stepId);
      // Auto-expand all namespaces on initial load (FR-18)
      _expandedNamespaces
        ..clear()
        ..addAll(namespaces);
    } catch (e) {
      _error = 'Failed to load factors: $e';
      _factors = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Called when a step-selected message is received.
  void onStepSelected(String workflowId, String stepId) {
    _hasStep = true;
    _workflowId = workflowId;
    _stepId = stepId;
    _searchQuery = ''; // FR-17: clear search on new step
    loadFactors(workflowId, stepId);
  }

  /// Update search query. Auto-expand matching namespace groups.
  void setSearchQuery(String value) {
    _searchQuery = value;

    if (value.isNotEmpty) {
      // Auto-expand namespaces that contain matches (FR-08)
      final query = value.toLowerCase();
      for (final entry in groupedFactors.entries) {
        if (entry.value.any((f) => f.name.toLowerCase().contains(query))) {
          _expandedNamespaces.add(entry.key);
        }
      }
    } else {
      // When search is cleared, expand all (FR-18 default)
      _expandedNamespaces
        ..clear()
        ..addAll(namespaces);
    }

    notifyListeners();
  }

  /// Toggle a namespace group's expand/collapse state.
  void toggleNamespace(String namespace) {
    if (_expandedNamespaces.contains(namespace)) {
      _expandedNamespaces.remove(namespace);
    } else {
      _expandedNamespaces.add(namespace);
    }
    notifyListeners();
  }
}
