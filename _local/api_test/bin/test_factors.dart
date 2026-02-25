import 'dart:convert';
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

/// Walk the Relation tree and collect all leaf relations.
/// This is the same logic as TercenFactorService._collectLeafRelations.
List<Relation> collectLeafRelations(Relation root) {
  final leaves = <Relation>[];

  void walk(Relation? rel) {
    if (rel == null) return;

    if (rel is SimpleRelation) {
      leaves.add(rel);
      return;
    }
    if (rel is InMemoryRelation) {
      return;
    }
    if (rel is CompositeRelation) {
      walk(rel.mainRelation);
      for (final jo in rel.joinOperators) {
        walk(jo.rightRelation);
      }
      return;
    }
    if (rel is UnionRelation) {
      for (final child in rel.relations) {
        walk(child);
      }
      return;
    }
    if (rel is SelectPairwiseRelation) {
      walk(rel.columnRelation);
      walk(rel.rowRelation);
      walk(rel.qtRelation);
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

    // Base Relation or unknown subtype — skip.
    // Only SimpleRelation/TableRelation reference stored table schemas.
    print('    [walker] skipping unknown ${rel.runtimeType} id="${rel.id}"');
  }

  walk(root);
  return leaves;
}

void main() async {
  print('=== Factor Loading Test ===');
  print('Server: $serviceUri');
  print('Team: $teamId\n');

  // 1. Create factory
  late ServiceFactory factory;
  try {
    factory = await createFactory();
    print('OK: Factory created\n');
  } catch (e) {
    print('FAIL: Factory creation: $e');
    exit(1);
  }

  // 2. Find a project with workflows
  print('--- Finding projects ---');
  final projects =
      await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(
    startKey: [teamId, false, ''],
    endKey: [teamId, true, '\uf000'],
    limit: 20,
    descending: false,
  );
  print('Found ${projects.length} projects');
  for (final p in projects) {
    print('  - ${p.name} (id=${p.id})');
  }
  if (projects.isEmpty) {
    print('No projects found. Cannot test factor loading.');
    exit(0);
  }

  // 3. For each project, find workflows and data steps
  for (final project in projects) {
    print('\n--- Project: ${project.name} ---');

    final docs = await factory.projectDocumentService
        .findProjectObjectsByFolderAndName(
      startKey: [project.id, '', ''],
      endKey: [project.id, '\uf000', '\uf000'],
      limit: 50,
      descending: false,
      useFactory: true,
    );

    final workflows = docs.whereType<Workflow>().toList();
    print('Found ${workflows.length} workflows');

    for (final wfDoc in workflows) {
      final wf = await factory.workflowService.get(wfDoc.id);
      print('\n  Workflow: ${wf.name} (${wf.steps.length} steps)');

      final dataSteps = wf.steps.whereType<DataStep>().toList();
      if (dataSteps.isEmpty) {
        print('  No DataSteps in this workflow');
        continue;
      }

      // Test factor loading on each DataStep
      for (final step in dataSteps) {
        print('\n  --- DataStep: ${step.name} (id=${step.id}) ---');
        print('  computedRelation type: ${step.computedRelation.runtimeType}');
        print('  computedRelation id: "${step.computedRelation.id}"');

        final leaves = collectLeafRelations(step.computedRelation);
        print('  Leaf relations: ${leaves.length}');
        for (final leaf in leaves) {
          print('    - ${leaf.runtimeType} id="${leaf.id}"');
        }

        // Fetch schemas and extract columns (= factors)
        final factors = <String, String>{}; // name -> type
        final seen = <String>{};

        for (final rel in leaves) {
          if (rel.id.isEmpty) {
            print('    (skipping empty id)');
            continue;
          }

          try {
            final schema = await factory.tableSchemaService.get(rel.id);
            print('    Schema ${rel.id}: ${schema.nRows} rows, ${schema.columns.length} columns');
            for (final col in schema.columns) {
              // Skip system columns (starting with . or being .base)
              if (col.name.startsWith('.')) continue;
              if (!seen.contains(col.name)) {
                seen.add(col.name);
                factors[col.name] = col.type;
              }
            }
          } catch (e) {
            print('    FAIL fetching schema ${rel.id}: $e');
          }
        }

        print('\n  FACTORS (${factors.length}):');
        final sortedNames = factors.keys.toList()..sort();
        for (final name in sortedNames) {
          // Parse namespace (everything before last dot)
          final dotIdx = name.lastIndexOf('.');
          final ns = dotIdx > 0 ? name.substring(0, dotIdx) : '(none)';
          final short = dotIdx > 0 ? name.substring(dotIdx + 1) : name;
          print('    [$ns] $short  (type: ${factors[name]})');
        }
      }
    }
  }

  print('\n=== Done ===');
  exit(0);
}
