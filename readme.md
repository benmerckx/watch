# watch

Creates a completion server and rebuilds the project on source file changes.  
Requires Haxe 4.2+

## Usage

<pre><a href="https://github.com/lix-pm/lix.client">lix</a> +lib watch</pre>

Append the library to the haxe build command:

<pre>haxe build.hxml -lib watch</pre>

> **Important:** Do not add this library to any hxml or config read by your IDE, autocompletion will not function.

Alternatively, just run it:

<pre><a href="https://github.com/lix-pm/lix.client">lix</a> watch build.hxml # (requires lix 15.11+)</pre>

### Defines

All of these are optional.

| Define                      | Description                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| `-D watch.run=(string)`     | command to execute on successful builds                                                     |
| `-D watch.port=(integer)`   | use this port for the completion server                                                     |
| `-D watch.connect`          | connect to a running completion server (use with `watch.port`)                              |
| `-D watch.excludeRoot`      | exclude watching the root directory (see [#3](https://github.com/benmerckx/watch/issues/3)) |
| `-D watch.exclude=(string)` | exclude this path from the watcher (can be repeated for multiple paths)                     |
| `-D watch.include=(string)` | include this path in the watcher (can be repeated for multiple paths)                       |
| `-D watch.verbose`          | extra log before and after every build                                                      |

### Example

Compiles test.js and runs the scripts with node on successful builds.

```
haxe --main Main --library hxnodejs --js test.js --library watch -D watch.run="node test.js"
```
