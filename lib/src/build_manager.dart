import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:conduit_isolate_executor/isolate_executor.dart';
import 'package:runtime/runtime.dart';

import 'build_context.dart';

class BuildExecutable extends Executable<Null> {
  BuildExecutable(Map<String, dynamic> message, {this.isFlutter})
      : super(message) {
    context = BuildContext.fromMap(message);
  }

  late BuildContext context;
  bool? isFlutter;

  @override
  Future<Null> execute() async {
    final build = Build(context);
    await build.execute(isFlutter: isFlutter);
  }
}

class BuildManager {
  /// Creates a new build manager to compile a non-mirrored build.
  BuildManager(this.context, {this.isFlutter});

  final BuildContext context;
  final bool? isFlutter;

  Uri get sourceDirectoryUri => context.sourceApplicationDirectory.uri;

  Future build() async {
    if (!context.buildDirectory.existsSync()) {
      context.buildDirectory.createSync();
    }

    // Here is where we need to provide a temporary copy of the script file with the main function stripped;
    // this is because when the RuntimeGenerator loads, it needs Mirror access to any declarations in this file
    var scriptSource = context.source;
    final strippedScriptFile = File.fromUri(context.targetScriptFileUri)
      ..writeAsStringSync(scriptSource);
    final analyzer = CodeAnalyzer(strippedScriptFile.absolute.uri);
    final analyzerContext = analyzer.contexts.contextFor(analyzer.path);
    final mainFunctions = analyzerContext.currentSession
        .getParsedUnit(analyzer.path)
        .unit
        .declarations
        .whereType<FunctionDeclaration>()
        .where((f) => f.name.name == "main")
        .toList();

    mainFunctions.reversed.forEach((f) {
      scriptSource = scriptSource.replaceRange(f.offset, f.end, "");
    });

    strippedScriptFile.writeAsStringSync(scriptSource);

    await IsolateExecutor.run(
        BuildExecutable(context.safeMap, isFlutter: isFlutter),
        packageConfigURI: sourceDirectoryUri.resolve(".packages"),
        imports: [
          "package:runtime/runtime.dart",
          context.targetScriptFileUri.toString()
        ],
        logHandler: (s) => print(s));
  }

  Future clean() async {
    if (context.buildDirectory.existsSync()) {
      context.buildDirectory.deleteSync(recursive: true);
    }
  }
}
