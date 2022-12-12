import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import '../elements/table_element.dart';
import '../schema.dart';
import '../utils.dart';


/// The main builder used for code generation
class AnalyzingBuilder implements Builder {
  /// The global options defined in the 'build.yaml' file
  late GlobalOptions options;

  AnalyzingBuilder(BuilderOptions options) : options = GlobalOptions.parse(options.config);

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    try {
      if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
        return;
      }
      var library = await buildStep.inputLibrary;
      await analyze(library, buildStep);
    } catch (e, st) {
      print('\x1B[31mFailed to build database schema:\n\n$e\x1B[0m\n');
      print(st);
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => const {'.dart': ['___']};

  Future<void> analyze(LibraryElement library, BuildStep buildStep) async {
    SchemaState schema = await buildStep.fetchResource(schemaResource);

    var asset = schema.createForAsset(buildStep.inputId);

    var builderState = BuilderState(options, schema, asset);

    var reader = LibraryReader(library);

    var tables = reader.annotatedWith(tableChecker);

    for (var table in tables) {
      asset.tables[table.element] = TableElement(
        table.element as ClassElement,
        table.annotation,
        builderState,
      );
    }
  }
}
