import 'package:flutter/foundation.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart'
    show ServiceFactory;

import '../../domain/models/factor.dart';
import '../../domain/services/data_service.dart';

/// Real Tercen implementation of DataService using entity services (Flow D).
///
/// For a given DataStep, walks the workflow link graph backward to find all
/// ancestor steps (TableSteps, DataSteps, etc.), then collects factors from
/// each ancestor's relation (TableStep.model.relation, DataStep.computedRelation).
class TercenFactorService implements DataService {
  final ServiceFactory _factory;

  TercenFactorService(this._factory);

  @override
  Future<List<Factor>> loadFactors(String workflowId, String stepId) async {
    debugPrint(
        'TercenFactorService.loadFactors: workflowId=$workflowId, stepId=$stepId');

    final workflow = await _factory.workflowService.get(workflowId);

    final step = workflow.steps.firstWhere(
      (s) => s.id == stepId,
      orElse: () => throw StateError(
          'Step $stepId not found in workflow $workflowId'),
    );

    if (step is! sci.DataStep) {
      throw StateError(
          'Step $stepId is ${step.runtimeType}, expected DataStep');
    }

    // Build step index
    final stepMap = <String, sci.Step>{};
    for (final s in workflow.steps) {
      stepMap[s.id] = s;
    }

    // Build reverse link graph: for each step, which steps feed into it?
    // Link.inputId = consumer port "{stepId}-i-{N}"
    // Link.outputId = producer port "{stepId}-o-{N}"
    final sourcesOf = <String, Set<String>>{};
    for (final link in workflow.links) {
      final consumerId = _extractStepId(link.inputId);
      final producerId = _extractStepId(link.outputId);
      if (consumerId != null && producerId != null) {
        sourcesOf.putIfAbsent(consumerId, () => {}).add(producerId);
      }
    }

    // BFS backward from the target step to find all ancestors
    final visited = <String>{};
    final queue = <String>[stepId];
    final ancestorSteps = <sci.Step>[];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current)) continue;

      final currentStep = stepMap[current];
      if (currentStep != null && currentStep.id != stepId) {
        ancestorSteps.add(currentStep);
      }

      final sources = sourcesOf[current] ?? {};
      queue.addAll(sources);
    }

    debugPrint(
        'TercenFactorService: found ${ancestorSteps.length} ancestor steps');

    // Collect factors from all ancestor relations + own computedRelation
    final factors = <Factor>[];
    final seen = <String>{};

    for (final anc in ancestorSteps) {
      sci.Relation? rel;
      if (anc is sci.TableStep) {
        rel = anc.model.relation;
      } else if (anc is sci.DataStep) {
        rel = anc.computedRelation;
      }
      if (rel != null) {
        await _collectFactorsFromRelation(rel, factors, seen);
      }
    }

    // Also include factors from the step's own computedRelation
    await _collectFactorsFromRelation(step.computedRelation, factors, seen);

    debugPrint('TercenFactorService: returning ${factors.length} factors');
    return factors;
  }

  /// Collect factors from a Relation by walking its tree to find leaf
  /// SimpleRelations, fetching their schemas, and extracting columns.
  Future<void> _collectFactorsFromRelation(
    sci.Relation relation,
    List<Factor> factors,
    Set<String> seen,
  ) async {
    final leaves = _collectLeafRelations(relation);
    for (final leaf in leaves) {
      if (leaf.id.isEmpty) continue;
      try {
        final schema = await _factory.tableSchemaService.get(leaf.id);
        for (final col in schema.columns) {
          final factor = Factor(name: col.name, type: col.type);
          if (!factor.isSystemColumn && seen.add(factor.name)) {
            factors.add(factor);
          }
        }
      } catch (e) {
        debugPrint(
            'TercenFactorService: skipping schema ${leaf.id}: $e');
      }
    }
  }

  /// Extract step ID from a link port ID like "stepId-i-0" or "stepId-o-0".
  static String? _extractStepId(String portId) {
    final match = RegExp(r'^(.+)-[io]-(\d+)$').firstMatch(portId);
    return match?.group(1);
  }

  /// Walk the Relation tree and collect all leaf SimpleRelations whose IDs
  /// reference stored table schemas.
  static List<sci.Relation> _collectLeafRelations(sci.Relation root) {
    final leaves = <sci.Relation>[];

    void walk(sci.Relation? rel) {
      if (rel == null) return;

      if (rel is sci.SimpleRelation) {
        leaves.add(rel);
        return;
      }
      if (rel is sci.InMemoryRelation) return;

      if (rel is sci.CompositeRelation) {
        walk(rel.mainRelation);
        for (final jo in rel.joinOperators) {
          walk(jo.rightRelation);
        }
        return;
      }
      if (rel is sci.UnionRelation) {
        for (final child in rel.relations) {
          walk(child);
        }
        return;
      }
      if (rel is sci.SelectPairwiseRelation) {
        walk(rel.columnRelation);
        walk(rel.rowRelation);
        walk(rel.qtRelation);
        return;
      }
      if (rel is sci.WhereRelation) { walk(rel.relation); return; }
      if (rel is sci.RenameRelation) { walk(rel.relation); return; }
      if (rel is sci.GatherRelation) { walk(rel.relation); return; }
      if (rel is sci.RangeRelation) { walk(rel.relation); return; }
      if (rel is sci.DistinctRelation) { walk(rel.relation); return; }
      if (rel is sci.PairwiseRelation) { walk(rel.relation); return; }
      if (rel is sci.GroupByRelation) { walk(rel.relation); return; }
      if (rel is sci.ReferenceRelation) { walk(rel.relation); return; }
    }

    walk(root);
    return leaves;
  }
}
