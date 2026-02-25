import 'package:flutter/foundation.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart'
    show ServiceFactory;
import 'package:widget_library/widget_library.dart' show Factor;

/// Result of ensuring a CubeQuery exists for a step with given bindings.
class CubeQueryResult {
  /// queryTableType → table ID (e.g., "qt" → "abc123", "column" → "def456").
  /// Classified by inspecting CubeQueryTableSchema.queryTableType for each
  /// schema ID, rather than trusting positional hash fields.
  final Map<String, String> tables;
  final int nRows;
  final sci.CubeQuery cubeQuery;

  CubeQueryResult({
    required this.tables,
    required this.nRows,
    required this.cubeQuery,
  });
}

/// Manages the CubeQuery lifecycle (5A/5B/5C) using sci_tercen_client.
///
/// Three flows:
/// - **5C** (match): existing CubeQuery has matching bindings → return as-is
/// - **5A** (mismatch): existing CubeQuery has different bindings → update + re-run
/// - **5B** (missing): no CubeQuery exists → build from scratch + run
class CubeQueryService {
  final ServiceFactory _factory;

  CubeQueryService(this._factory);

  /// Ensure a CubeQuery exists for the given step with matching bindings.
  Future<CubeQueryResult> ensureCubeQuery({
    required String workflowId,
    required String stepId,
    required String? xColumn,
    required String? yColumn,
    required List<String> colFacetColumns,
    required List<String> rowFacetColumns,
  }) async {
    debugPrint('CubeQueryService: ensuring CubeQuery for step $stepId');

    // Always fetch workflow — needed for projectId (all paths) and relation (5B)
    final workflow = await _factory.workflowService.get(workflowId);
    final step = workflow.steps.firstWhere(
      (s) => s.id == stepId,
      orElse: () =>
          throw StateError('Step $stepId not found in workflow $workflowId'),
    );

    // Try to get existing CubeQuery
    sci.CubeQuery? existingCq;
    try {
      existingCq = await _factory.workflowService.getCubeQuery(
        workflowId,
        stepId,
      );
    } catch (e) {
      debugPrint('CubeQueryService: getCubeQuery failed: $e');
      // Treat as 5B — no existing CubeQuery
    }

    if (existingCq != null) {
      final bindingsMatch = _checkBindingsMatch(
        existingCq,
        xColumn: xColumn,
        yColumn: yColumn,
        colFacetColumns: colFacetColumns,
        rowFacetColumns: rowFacetColumns,
      );

      if (bindingsMatch && existingCq.qtHash.isNotEmpty) {
        // PATH 5C: match — return existing
        debugPrint('CubeQueryService: 5C path — bindings match');
        final schemaIds = await _getSchemaIdsFromStep(step);
        final classified = await _classifySchemas(schemaIds);
        if (classified.tables['qt'] == null) {
          throw StateError(
            'Schema classification found no qt table for step $stepId '
            '(schemaIds: $schemaIds, classified: ${classified.tables})',
          );
        }
        return CubeQueryResult(
          tables: classified.tables,
          nRows: classified.qtNRows,
          cubeQuery: existingCq,
        );
      }

      // PATH 5A: mismatch — update bindings and re-run
      debugPrint('CubeQueryService: 5A path — updating bindings');
      _updateBindings(
        existingCq,
        xColumn: xColumn,
        yColumn: yColumn,
        colFacetColumns: colFacetColumns,
        rowFacetColumns: rowFacetColumns,
      );
      return _runCubeQueryTask(
        existingCq, workflow.projectId, workflow.acl.owner);
    }

    // PATH 5B: no existing CubeQuery — build from scratch
    debugPrint('CubeQueryService: 5B path — building from scratch');
    final freshCq = _buildFreshCubeQuery(
      workflow,
      step,
      xColumn: xColumn,
      yColumn: yColumn,
      colFacetColumns: colFacetColumns,
      rowFacetColumns: rowFacetColumns,
    );
    return _runCubeQueryTask(
      freshCq, workflow.projectId, workflow.acl.owner);
  }

  /// Fetch the existing CubeQuery for a step and extract its bindings.
  ///
  /// Returns null if no CubeQuery exists or if it has no Y binding.
  /// Used on step selection to restore previous bindings before rendering.
  Future<
      ({
        Factor? x,
        Factor y,
        List<Factor> colFacets,
        List<Factor> rowFacets,
      })?> fetchExistingBindings({
    required String workflowId,
    required String stepId,
  }) async {
    final sci.CubeQuery cq;
    try {
      cq = await _factory.workflowService.getCubeQuery(workflowId, stepId);
    } catch (e) {
      debugPrint('CubeQueryService: fetchExistingBindings failed: $e');
      return null;
    }

    // Extract Y — if empty, no usable bindings
    final yName = cq.axisQueries.isNotEmpty
        ? cq.axisQueries.first.yAxis.name
        : '';
    if (yName.isEmpty) return null;

    final yType = cq.axisQueries.first.yAxis.type;

    // Extract X (may be empty)
    final xName = cq.axisQueries.isNotEmpty
        ? cq.axisQueries.first.xAxis.name
        : '';
    final xType = cq.axisQueries.isNotEmpty
        ? cq.axisQueries.first.xAxis.type
        : '';

    // Extract facets
    final colFacets = cq.colColumns
        .where((f) => f.name.isNotEmpty)
        .map((f) => Factor(name: f.name, type: f.type))
        .toList();
    final rowFacets = cq.rowColumns
        .where((f) => f.name.isNotEmpty)
        .map((f) => Factor(name: f.name, type: f.type))
        .toList();

    debugPrint(
      'CubeQueryService: existing bindings — '
      'y=$yName, x=$xName, '
      '${colFacets.length} col facets, ${rowFacets.length} row facets',
    );

    return (
      x: xName.isNotEmpty ? Factor(name: xName, type: xType) : null,
      y: Factor(name: yName, type: yType),
      colFacets: colFacets,
      rowFacets: rowFacets,
    );
  }

  /// Check if the existing CubeQuery's bindings match the requested ones.
  bool _checkBindingsMatch(
    sci.CubeQuery cq, {
    required String? xColumn,
    required String? yColumn,
    required List<String> colFacetColumns,
    required List<String> rowFacetColumns,
  }) {
    // Check Y axis
    final existingY = cq.axisQueries.isNotEmpty
        ? cq.axisQueries.first.yAxis.name
        : '';
    final yMatch = (yColumn ?? '') == existingY;

    // Check X axis
    final existingX = cq.axisQueries.isNotEmpty
        ? cq.axisQueries.first.xAxis.name
        : '';
    final xMatch = (xColumn ?? '') == existingX;

    // Check col facets (order-sensitive list comparison)
    final existingColFacets =
        cq.colColumns.map((f) => f.name).toList();
    final colMatch = _listsEqual(colFacetColumns, existingColFacets);

    // Check row facets (order-sensitive list comparison)
    final existingRowFacets =
        cq.rowColumns.map((f) => f.name).toList();
    final rowMatch = _listsEqual(rowFacetColumns, existingRowFacets);

    return yMatch && xMatch && colMatch && rowMatch;
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Update CubeQuery bindings in-place.
  void _updateBindings(
    sci.CubeQuery cq, {
    required String? xColumn,
    required String? yColumn,
    required List<String> colFacetColumns,
    required List<String> rowFacetColumns,
  }) {
    // Ensure at least one axis query exists
    if (cq.axisQueries.isEmpty) {
      cq.axisQueries.add(sci.CubeAxisQuery());
    }
    final aq = cq.axisQueries.first;

    if (yColumn != null) {
      aq.yAxis = sci.Factor()
        ..name = yColumn
        ..type = 'double';
    }
    if (xColumn != null) {
      aq.xAxis = sci.Factor()
        ..name = xColumn
        ..type = 'double';
    }

    cq.colColumns.clear();
    for (final col in colFacetColumns) {
      cq.colColumns.add(
        sci.Factor()
          ..name = col
          ..type = 'string',
      );
    }

    cq.rowColumns.clear();
    for (final row in rowFacetColumns) {
      cq.rowColumns.add(
        sci.Factor()
          ..name = row
          ..type = 'string',
      );
    }
  }

  /// Build a fresh CubeQuery from the workflow's step relation.
  sci.CubeQuery _buildFreshCubeQuery(
    sci.Workflow workflow,
    sci.Step step, {
    required String? xColumn,
    required String? yColumn,
    required List<String> colFacetColumns,
    required List<String> rowFacetColumns,
  }) {
    final relation = _getInputRelation(workflow, step.id);

    final aq = sci.CubeAxisQuery();
    if (yColumn != null) {
      aq.yAxis = sci.Factor()
        ..name = yColumn
        ..type = 'double';
    }
    if (xColumn != null) {
      aq.xAxis = sci.Factor()
        ..name = xColumn
        ..type = 'double';
    }

    final cq = sci.CubeQuery()
      ..relation = relation
      ..filters = (sci.Filters()..removeNaN = true)
      ..operatorSettings = sci.OperatorSettings();

    cq.axisQueries.add(aq);

    for (final col in colFacetColumns) {
      cq.colColumns.add(
        sci.Factor()
          ..name = col
          ..type = 'string',
      );
    }
    for (final row in rowFacetColumns) {
      cq.rowColumns.add(
        sci.Factor()
          ..name = row
          ..type = 'string',
      );
    }

    return cq;
  }

  /// Walk the workflow link graph to find the input relation for a step.
  sci.Relation _getInputRelation(sci.Workflow workflow, String stepId) {
    final portIdRegex = RegExp(r'^(.+)-[io]-(\d+)$');

    // Build step lookup
    final stepMap = <String, sci.Step>{};
    for (final s in workflow.steps) {
      stepMap[s.id] = s;
    }

    // Walk links to find parent step
    for (final link in workflow.links) {
      final consumerMatch = portIdRegex.firstMatch(link.inputId);
      final producerMatch = portIdRegex.firstMatch(link.outputId);

      final consumerId = consumerMatch?.group(1);
      final producerId = producerMatch?.group(1);

      if (consumerId == stepId && producerId != null) {
        final parentStep = stepMap[producerId];
        if (parentStep is sci.TableStep) {
          return parentStep.model.relation;
        }
        if (parentStep is sci.DataStep) {
          return parentStep.computedRelation;
        }
      }
    }

    // Fallback: use the target step's own computed relation
    final step = stepMap[stepId];
    if (step is sci.DataStep) {
      return step.computedRelation;
    }

    throw StateError('Cannot find input relation for step $stepId');
  }

  /// Create and run a CubeQueryTask, wait for completion, return result.
  Future<CubeQueryResult> _runCubeQueryTask(
    sci.CubeQuery cubeQuery,
    String projectId,
    String owner,
  ) async {
    final task = sci.CubeQueryTask()
      ..query = cubeQuery
      ..projectId = projectId
      ..state = sci.InitState()
      ..owner = owner
      ..isDeleted = false;

    final created = await _factory.taskService.create(task);
    debugPrint('CubeQueryService: task created: ${created.id}');

    await _factory.taskService.runTask(created.id);
    debugPrint('CubeQueryService: task running, waiting...');

    final done = await _factory.taskService.waitDone(created.id);

    if (done.state is sci.FailedState) {
      final failed = done.state as sci.FailedState;
      throw StateError(
        'CubeQueryTask failed: ${failed.reason}',
      );
    }

    debugPrint('CubeQueryService: task completed');

    // Extract result from completed task
    final cqTask = done as sci.CubeQueryTask;
    final resultCq = cqTask.query;
    final schemaIds = cqTask.schemaIds.toList();
    final classified = await _classifySchemas(schemaIds);

    return CubeQueryResult(
      tables: classified.tables,
      nRows: classified.qtNRows,
      cubeQuery: resultCq,
    );
  }

  /// Classify schema IDs by their queryTableType.
  /// Returns the tables map and the qt table's nRows (extracted from the same
  /// batch fetch — no extra HTTP call needed).
  /// Single batch HTTP call via tableSchemaService.list().
  Future<({Map<String, String> tables, int qtNRows})> _classifySchemas(
    List<String> schemaIds,
  ) async {
    final tables = <String, String>{};
    final validIds = schemaIds.where((id) => id.isNotEmpty).toList();
    if (validIds.isEmpty) return (tables: tables, qtNRows: 0);

    int qtNRows = 0;
    final schemas = await _factory.tableSchemaService.list(validIds);
    for (final schema in schemas) {
      if (schema is sci.CubeQueryTableSchema) {
        tables[schema.queryTableType] = schema.id;
        if (schema.queryTableType == 'qt') {
          qtNRows = schema.nRows;
        }
      }
    }
    debugPrint('CubeQueryService: classified schemas: $tables (qt nRows=$qtNRows)');
    return (tables: tables, qtNRows: qtNRows);
  }

  /// Get schemaIds from the step's associated CubeQueryTask (for 5C path).
  Future<List<String>> _getSchemaIdsFromStep(sci.Step step) async {
    if (step is! sci.DataStep) return [];
    final taskId = step.model.taskId;
    if (taskId.isEmpty) return [];

    final task = await _factory.taskService.get(taskId);
    if (task is sci.CubeQueryTask) {
      return task.schemaIds.toList();
    }
    return [];
  }
}
