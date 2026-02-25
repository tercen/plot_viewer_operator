import 'dart:io';

import 'package:sci_tercen_client/sci_client.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_http_client/http_io_client.dart';
import 'package:sci_http_client/http_auth_client.dart';

const token =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vMTI3LjAuMC4xOjU0MDAiLCJleHAiOjE3NzM5MjEzMTksImRhdGEiOnsiZCI6IiIsInUiOiJ0ZXN0IiwiZSI6MTc3MzkyMTMxOTQ1M319.EJH25KY56XnzLLFbBe9K10PS4KFjGLWvVn4B07b_SOM';
const serviceUri = 'http://127.0.0.1:5400';
const teamId = 'test';

Future<ServiceFactory> createFactory() async {
  HttpIOClient.setAsCurrent();
  var httpClient = HttpAuthClient(token) as http_api.HttpClient;
  var factory = ServiceFactory();
  await factory.initializeWith(Uri.parse(serviceUri), httpClient);
  return factory;
}

/// Extract step ID from a link port ID like "stepId-i-0" or "stepId-o-0".
String? extractStepId(String portId) {
  // Pattern: {stepId}-i-{N} or {stepId}-o-{N}
  final match = RegExp(r'^(.+)-[io]-(\d+)$').firstMatch(portId);
  return match?.group(1);
}

/// Walk the Relation tree and collect leaf SimpleRelations.
List<Relation> collectLeafRelations(Relation root) {
  final leaves = <Relation>[];
  void walk(Relation? rel) {
    if (rel == null) return;
    if (rel is SimpleRelation) { leaves.add(rel); return; }
    if (rel is InMemoryRelation) return;
    if (rel is CompositeRelation) {
      walk(rel.mainRelation);
      for (final jo in rel.joinOperators) walk(jo.rightRelation);
      return;
    }
    if (rel is UnionRelation) { for (final c in rel.relations) walk(c); return; }
    if (rel is SelectPairwiseRelation) {
      walk(rel.columnRelation); walk(rel.rowRelation); walk(rel.qtRelation);
      return;
    }
    if (rel is WhereRelation) { walk(rel.relation); return; }
    if (rel is RenameRelation) { walk(rel.relation); return; }
    if (rel is GatherRelation) { walk(rel.relation); return; }
    if (rel is RangeRelation) { walk(rel.relation); return; }
    if (rel is DistinctRelation) { walk(rel.relation); return; }
    if (rel is PairwiseRelation) { walk(rel.relation); return; }
    if (rel is GroupByRelation) { walk(rel.relation); return; }
    if (rel is ReferenceRelation) { walk(rel.relation); return; }
  }
  walk(root);
  return leaves;
}

/// Fetch factors (column names) from leaf relations of a Relation.
Future<Map<String, String>> fetchFactorsFromRelation(
    ServiceFactory factory, Relation relation) async {
  final factors = <String, String>{};
  final leaves = collectLeafRelations(relation);
  for (final leaf in leaves) {
    if (leaf.id.isEmpty) continue;
    try {
      final schema = await factory.tableSchemaService.get(leaf.id);
      for (final col in schema.columns) {
        if (!col.name.startsWith('.')) {
          factors[col.name] = col.type;
        }
      }
    } catch (_) {}
  }
  return factors;
}

void main() async {
  print('=== Step Links & Factor Chain Test (v2 — port-aware) ===\n');

  final factory = await createFactory();
  print('OK: Factory created\n');

  final projects =
      await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(
    startKey: [teamId, false, ''],
    endKey: [teamId, true, '\uf000'],
    limit: 20,
    descending: false,
  );

  for (final project in projects) {
    final docs = await factory.projectDocumentService
        .findProjectObjectsByFolderAndName(
      startKey: [project.id, '', ''],
      endKey: [project.id, '\uf000', '\uf000'],
      limit: 50,
      descending: false,
      useFactory: true,
    );
    final workflows = docs.whereType<Workflow>().toList();
    if (workflows.isEmpty) continue;

    for (final wfDoc in workflows) {
      final wf = await factory.workflowService.get(wfDoc.id);
      if (wf.steps.length < 2) continue;

      print('=== Project: ${project.name} / Workflow: ${wf.name} ===');
      print('Steps: ${wf.steps.length}, Links: ${wf.links.length}\n');

      // Build step index
      final stepMap = <String, Step>{};
      for (final step in wf.steps) {
        stepMap[step.id] = step;
      }

      // Build link graph: inputStepId -> [outputStepIds] (data flows from output to input)
      // Link.inputId = consumer port (stepId-i-N)
      // Link.outputId = producer port (stepId-o-N)
      // So for step C, find links where inputId starts with C → those give C's data sources.
      final sourcesOf = <String, Set<String>>{}; // consumer stepId -> {producer stepIds}

      print('--- LINKS (parsed) ---');
      for (final link in wf.links) {
        final consumerId = extractStepId(link.inputId);
        final producerId = extractStepId(link.outputId);
        if (consumerId != null && producerId != null) {
          sourcesOf.putIfAbsent(consumerId, () => {}).add(producerId);
          final consumerName = stepMap[consumerId]?.name ?? '?';
          final producerName = stepMap[producerId]?.name ?? '?';
          print('  "$producerName" ($producerId) --> "$consumerName" ($consumerId)');
        }
      }

      // For each DataStep, walk backward through links and collect all ancestor factors
      print('\n--- FACTOR CHAINS ---');
      final dataSteps = wf.steps.whereType<DataStep>().toList();

      // Only test first 3 DataSteps per workflow to keep output manageable
      for (final ds in dataSteps.take(3)) {
        print('\n  DataStep: "${ds.name}" (${ds.id})');

        // BFS backward through links
        final visited = <String>{};
        final queue = <String>[ds.id];
        final ancestors = <Step>[];

        while (queue.isNotEmpty) {
          final current = queue.removeAt(0);
          if (!visited.add(current)) continue;

          final step = stepMap[current];
          if (step != null && step.id != ds.id) {
            ancestors.add(step);
          }

          // Follow links backward: find all sources for this step
          final sources = sourcesOf[current] ?? {};
          queue.addAll(sources);
        }

        print('    Ancestors (${ancestors.length}):');
        for (final anc in ancestors) {
          print('      - [${anc.runtimeType}] "${anc.name}" (${anc.id})');
        }

        // Collect factors from all ancestors
        final allFactors = <String, String>{};

        for (final anc in ancestors) {
          Relation? rel;
          if (anc is TableStep) {
            rel = anc.model.relation;
            print('    TableStep "${anc.name}" relation: ${rel.runtimeType} id="${rel.id}"');
          } else if (anc is DataStep) {
            rel = anc.computedRelation;
            print('    DataStep "${anc.name}" computedRelation: ${rel.runtimeType} id="${rel.id}"');
          }
          if (rel != null) {
            final f = await fetchFactorsFromRelation(factory, rel);
            print('      -> ${f.length} factors: ${f.keys.take(10).join(", ")}${f.length > 10 ? "..." : ""}');
            allFactors.addAll(f);
          }
        }

        // Also collect from own computedRelation
        final ownF = await fetchFactorsFromRelation(factory, ds.computedRelation);
        print('    Self computedRelation: ${ds.computedRelation.runtimeType} -> ${ownF.length} factors');
        allFactors.addAll(ownF);

        print('    TOTAL FACTORS: ${allFactors.length}');
        final sorted = allFactors.keys.toList()..sort();
        for (final name in sorted) {
          print('      $name (${allFactors[name]})');
        }
      }

      print('\n');
    }
  }

  print('=== Done ===');
  exit(0);
}
