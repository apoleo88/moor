// Mega compilation unit that includes all Dart apis related to generating SQL
// at runtime.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:drift/internal/versioned_schema.dart';
import 'package:drift/src/dsl/dsl.dart';
import 'package:drift/src/runtime/api/options.dart';
import 'package:drift/src/runtime/api/runtime_api.dart';
import 'package:drift/src/runtime/data_class.dart';
import 'package:drift/src/runtime/data_verification.dart';
import 'package:drift/src/runtime/exceptions.dart';
import 'package:drift/src/runtime/executor/stream_queries.dart';
import 'package:drift/src/runtime/types/converters.dart';
import 'package:drift/src/runtime/types/mapping.dart';
import 'package:drift/src/utils/async_map.dart';
import 'package:drift/src/utils/single_transformer.dart';
import 'package:meta/meta.dart';

import '../../utils/async.dart';
import '../utils.dart';
// New files should not be part of this mega library, which we're trying to
// split up.

import 'expressions/case_when.dart';
import 'expressions/internal.dart';
import 'helpers.dart';

export 'components/table_valued_function.dart';
export 'expressions/bitwise.dart';
export 'expressions/case_when.dart';
export 'on_table.dart';

part 'components/group_by.dart';
part 'components/join.dart';
part 'components/limit.dart';
part 'components/order_by.dart';
part 'components/subquery.dart';
part 'components/where.dart';
part 'expressions/aggregate.dart';
part 'expressions/algebra.dart';
part 'expressions/bools.dart';
part 'expressions/comparable.dart';
part 'expressions/custom.dart';
part 'expressions/datetimes.dart';
part 'expressions/exists.dart';
part 'expressions/expression.dart';
part 'expressions/in.dart';
part 'expressions/null_check.dart';
part 'expressions/text.dart';
part 'expressions/variables.dart';
part 'generation_context.dart';
part 'migration.dart';
part 'schema/column_impl.dart';
part 'schema/entities.dart';
part 'schema/table_info.dart';
part 'schema/view_info.dart';
part 'statements/delete.dart';
part 'statements/insert.dart';
part 'statements/query.dart';
part 'statements/select/custom_select.dart';
part 'statements/select/select.dart';
part 'statements/select/select_with_join.dart';
part 'statements/update.dart';

/// A component is anything that can appear in a sql query.
abstract class Component {
  /// Default, constant constructor.
  const Component();

  /// Writes this component into the [context] by writing to its
  /// [GenerationContext.buffer] or by introducing bound variables. When writing
  /// into the buffer, no whitespace around the this component should be
  /// introduced. When a component consists of multiple composed component, it's
  /// responsible for introducing whitespace between its child components.
  void writeInto(GenerationContext context);
}

/// Writes all [components] into the [context], separated by commas.
void _writeCommaSeparated(
    GenerationContext context, Iterable<Component> components) {
  var first = true;
  for (final element in components) {
    if (!first) {
      context.buffer.write(', ');
    }
    element.writeInto(context);
    first = false;
  }
}

/// An enumeration of database systems supported by drift. Only
/// [SqlDialect.sqlite] is officially supported, all others are in an
/// experimental state at the moment.
enum SqlDialect {
  /// Use sqlite's sql dialect. This is the default option and the only
  /// officially supported dialect at the moment.
  sqlite(
    booleanType: 'INTEGER',
    textType: 'TEXT',
    integerType: 'INTEGER',
    realType: 'REAL',
    blobType: 'BLOB',
  ),

  /// (currently unsupported)
  @Deprecated('Use mariadb instead, even when talking to a MySQL database')
  mysql(
    booleanType: '',
    textType: '',
    integerType: '',
    blobType: '',
    realType: '',
  ),

  /// PostgreSQL (currently supported in an experimental state)
  postgres(
    booleanType: 'boolean',
    textType: 'text',
    integerType: 'bigint',
    blobType: 'bytea',
    realType: 'float8',
  ),

  /// MariaDB (currently supported in an experimental state)
  mariadb(
    booleanType: 'BOOLEAN',
    textType: 'TEXT',
    integerType: 'BIGINT',
    blobType: 'BLOB',
    realType: 'DOUBLE',
    escapeChar: '`',
    supportsIndexedParameters: false,
  );

  /// The type to use in `CAST`s and column definitions to store booleans.
  final String booleanType;

  /// The type to use in `CAST`s and column definitions to store strings.
  final String textType;

  /// The type to use in `CAST`s and column definitions to store 64-bit
  /// integers.
  final String integerType;

  /// The type to use in `CAST`s and column definitions to store doubles.
  final String realType;

  /// The type to use in `CAST`s and column definitions to store blobs (as
  /// a [Uint8List] in Dart).
  final String blobType;

  /// The character used to wrap identifiers to distinguish them from keywords.
  ///
  /// This is a double quote character in ANSI SQL, but MariaDB uses backticks
  /// by default.
  final String escapeChar;

  /// Whether this dialect supports indexed parameters.
  ///
  /// For dialects that support this features, an explicit index can be given
  /// for parameters, even if it doesn't match the order of occurrences in the
  /// given statement (e.g. `INSERT INTO foo VALUES (?1, ?2, ?3, ?4)`).
  /// In dialects without this feature, every syntactic occurrence of a variable
  /// introduces a new logical variable with a new index, variables also can't
  /// be re-used.
  final bool supportsIndexedParameters;

  /// Escapes [identifier] by wrapping it in [escapeChar].
  String escape(String identifier) => '$escapeChar$identifier$escapeChar';

  const SqlDialect({
    required this.booleanType,
    required this.textType,
    required this.integerType,
    required this.realType,
    required this.blobType,
    this.escapeChar = '"',
    this.supportsIndexedParameters = true,
  });

  /// For dialects that don't support named or explicitly-indexed variables,
  /// translates a variable assignment to avoid using that feature.
  ///
  /// For instance, the SQL snippet `WHERE x = :a OR y = :a` would be translated
  /// to `WHERE x = ? OR y = ?`. Then, [original] would contain the value for
  /// the single variable and [syntacticOccurences] would contain two values
  /// (`1` and `1`) referencing the original variable.
  List<Variable> desugarDuplicateVariables(
    List<Variable> original,
    List<int> syntacticOccurences,
  ) {
    if (supportsIndexedParameters) return original;

    return [
      for (final occurence in syntacticOccurences)
        // Variables in SQL are 1-indexed
        original[occurence - 1],
    ];
  }
}
