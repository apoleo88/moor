---
data:
  title: Runtime schema inspection
  description: Use generated table classes to reflectively inspect the schema of your database.
template: layouts/docs/single

aliases:
  - docs/advanced-features/schema_inspection/
---

{% assign snippets = 'package:drift_docs/snippets/modular/schema_inspection.dart.excerpt.json' | readString | json_decode %}

Thanks to the typesafe table classes generated by drift, [writing SQL queries]({{ '../Dart API/select.md' | pageUrl }}) in Dart
is simple and safe.
However, these queries are usually written against a specific table. And while drift supports inheritance for tables, sometimes it is easier
to access tables reflectively. Luckily, code generated by drift implements interfaces which can be used to do just that.

Since this is a topic that most drift users will not need, this page mostly gives motivating examples and links to the documentation for relevant
drift classes.
For instance, you might have multiple independent tables that have an `id` column. And you might want to filter rows by their `id` column.
When writing this query against a single table, like the `Todos` table as seen in the [getting started]({{'../setup.md' | pageUrl }}) page,
that's pretty straightforward:

{% include "blocks/snippet" snippets = snippets name = 'findTodoEntryById' %}

But let's say we want to generalize this query to every database table, how could that look like?
This following snippet shows how this can be done (note that the links in the snippet point directly towards the relevant documentation):

{% include "blocks/snippet" snippets = snippets name = 'findById' %}

Since that is much more complicated than the query that only works for a single table, let's take a look at each interesting line in detail:

 - `FindById` is an extension on [ResultSetImplementation]. This class is the superclass for every table or view generated by drift.
   It defines useful methods to inspect the schema, or to translate a raw `Map` representing a database row into the generated data class.
   - `ResultSetImplementation` is instantiated with two type arguments: The original table class and the generated row class.
    For instance, if you define a table `class Todos extends Table`, drift would generate a class that extends `Todos` while also implementing.
    `ResultSetImplementation<Todos, Todo>` (with `Todo` being the generated data class).
   - `ResultSetImplementation` has two subclasses: [TableInfo] and [ViewInfo] which are mixed in to generated table and view classes, respectively.
   - `HasResultSet` is the superclass for `Table` and `View`, the two classes used to declare tables and views in drift.
- `Selectable<Row>` represents a query, you can use methods like `get()`, `watch()`, `getSingle()` and `watchSingle()` on it to run the query.
- The `select()` extension used in `findById` can be used to start a select statement without a reference to a database class - all you need is
  the table instance.
- We can use `columnsByName` to find a column by its name in SQL. Here, we expect an `int` column to exist.
- The [GeneratedColumn] class represents a column in a database. Things like column constraints, the type or default values can be read from the
  column instance.
  - In particular, we use this to assert that the table indeed has an `IntColumn` named `id`.

To call this extension, `await myDatabase.todos.findById(3).getSingle()` could be used.
A nice thing about defining the method as an extension is that type inference works really well - calling `findById` on `todos`
returns a `Todo` instance, the generated data class for this table.

The same approach also works to construct update, delete and insert statements (although those require a [TableInfo] instead of a [ResultSetImplementation]
as views are read-only).

Hopefully, this page gives you some pointers to start reflectively inspecting your drift databases.
The linked Dart documentation also expains the concepts in more detail.
If you have questions about this, or have a suggestion for more examples to include on this page, feel free to [start a discussion](https://github.com/simolus3/drift/discussions/new?category=q-a) about this.

[ResultSetImplementation]: https://drift.simonbinder.eu/api/drift/resultsetimplementation-class
[TableInfo]: https://drift.simonbinder.eu/api/drift/tableinfo-mixin
[ViewInfo]: https://drift.simonbinder.eu/api/drift/viewinfo-class
[GeneratedColumn]: https://drift.simonbinder.eu/api/drift/generatedcolumn-class