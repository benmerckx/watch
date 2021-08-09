# watch

Creates a completion server and rebuilds the project on source file changes.  
Requires Haxe 4.2+

## Usage

```
lix +lib watch
```

Append the library to the haxe build command:

```
haxe build.hxml -lib watch
```

> **Important:** Do not add this library to any hxml or config read by your IDE, autocompletion will not function.

### Defines

All of these are optional.

| Define                    | Description                                                    |
| ------------------------- | -------------------------------------------------------------- |
| `-D watch.run=(string)`   | command to execute on successful builds                        |
| `-D watch.port=(integer)` | use this port for the completion server                        |
| `-D watch.connect`        | connect to a running completion server (use with `watch.port`) |

### Example

Compiles test.js and runs the scripts with node on successful builds.

```
haxe --main Main --library hxnodejs --js test.js --library watch -D watch.run="node test.js"
```
