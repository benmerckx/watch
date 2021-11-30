package watch;

import eval.NativeString;
import eval.luv.Timer;
import eval.luv.FsEvent;
import eval.luv.Process;
import eval.luv.SockAddr;
import eval.luv.Tcp;
import haxe.macro.Context;
import haxe.io.Path;
import sys.FileSystem;
using StringTools;
using Lambda;

private final loop = sys.thread.Thread.current().events;

private function fail(message: String, ?error: Dynamic) {
  Sys.println(message);
  if (error != null) 
    Sys.print('$error');
  Sys.exit(1);
}

private final noInputOptions = [
  'interp', 'haxelib-global', 'no-traces', 'no-output', 'no-inline', 'no-opt',
  'v', 'verbose', 'debug', 'prompt', 'times', 'next', 'each', 'flash-strict'
];

private final outputs = ['php', 'cpp', 'cs', 'java'];

function buildArguments(args: Array<String>): BuildConfig {
  final arguments = [];
  final excludes = [];
  final includes = [];
  final forward = [];
  final dist = [];
  var i = 0;
  function skip() i++;
  while (i < args.length) {
    switch [args[i], args[i + 1]] {
      case 
        ['-L' | '-lib' | '--library', 'watch'],
        ['--macro', 'watch.Watch.register()']:
        skip();
      case ['-D' | '--define', define] if (define.startsWith('watch.exclude')):
        excludes.push(define.substr(define.indexOf('=') + 1));
        skip();
      case ['-D' | '--define', define] if (define.startsWith('watch.include')):
        includes.push(define.substr(define.indexOf('=') + 1));
        skip();
      case [arg, next]:
          final option = arg.startsWith('--') ? arg.substr(2) : arg.substr(1);
          if (outputs.indexOf(option) > -1) 
            dist.push(next);
        forward.push(args[i]);
    }
    skip();
  }
  var inputExpected = false;
  for (arg in forward) {
    final isOption = arg.startsWith('-');
    if (inputExpected && !isOption) arguments[arguments.length - 1] += ' $arg';
    else arguments.push(arg);
    final option = arg.startsWith('--') ? arg.substr(2) : arg.substr(1);
    inputExpected = 
      isOption && noInputOptions.indexOf(option) == -1;
  }
  return {arguments: arguments, excludes: excludes, includes: includes, dist: dist}
}

typedef BuildConfig = {
  arguments: Array<String>,
  excludes: Array<String>,
  includes: Array<String>,
  dist: Array<String>
}

function isSubOf(path: String, parent: String) {
  var a = Path.normalize(path);
  var b = Path.normalize(parent);
  final caseInsensitive = Sys.systemName() == 'Windows';
  if (caseInsensitive) {
    a = a.toLowerCase();
    b = b.toLowerCase();
  }
  return a.startsWith(b + '/');
}

function pathIsIn(path: String, candidates: Array<String>) {
  return candidates.exists(parent -> path == parent || isSubOf(path, parent));
}

function dedupePaths(paths: Array<String>) {
  final res = [];
  final todo = paths.slice(0);
  todo.sort((a, b) -> {
    return b.length - a.length;
  });
  for (i in 0 ...todo.length) {
    final path = todo[i];
    final isSubOfNext = pathIsIn(path, todo.slice(i + 1));
    if (!isSubOfNext) res.push(path);
  }
  return res;
}

typedef Server = {
  build: (config: BuildConfig, done: (hasError: Bool) -> Void) -> Void,
  close: (done: () -> Void) -> Void
}

function createServer(port: Int, cb: (server: Server) -> Void) {
  if (Context.defined('watch.connect'))
    return cb({
      build: (config, done) -> createBuild(port, config, done),
      close: (done) -> done()
    });
  final stdout = Process.inheritFd(Process.stdout, Process.stdout);
  final stderr = Process.inheritFd(Process.stderr, Process.stderr);
  function start(extension = '') {
    switch Process.spawn(loop, 'haxe' + extension, ['haxe', '--wait', '$port'], {
      redirect: [stdout, stderr],
      onExit: (_, exitStatus, _) -> fail('Completion server exited', exitStatus)
    }) {
      case Ok(process):
        cb({
          build: (config, done) -> {
            createBuild(port, config, done);
          },
          close: (done) -> process.close(done)
        });
      case Error(UV_ENOENT) if (Sys.systemName() == 'Windows' && extension == ''):
        start('.cmd');
      case Error(e): fail('Could not start completion server, is haxe in path?', e);
    }
  }
  switch [SockAddr.ipv4('127.0.0.1', port), Tcp.init(loop)] {
    case [Ok(addr), Ok(socket)]:
      socket.connect(addr, res -> switch res {
        case Ok(_):
          socket.close(() -> {
            createServer(port + 1, cb);
          });
        case Error(_):
          socket.close(() -> start());
      });
    case [_, Error(e)] | [Error(e), _]: 
      fail('Could not check if port is open', e);
  }
}

private function shellOut(command: String) {
  return switch Sys.systemName() {
    case 'Windows': ['cmd.exe', '/c', command];
    default: ['sh', '-c', command];
  }
}  

function runCommand(command: String) {
  final args = shellOut(command).map(NativeString.fromString);
  final stdout = Process.inheritFd(Process.stdout, Process.stdout);
  final stderr = Process.inheritFd(Process.stderr, Process.stderr);
  var exited = false;
  return switch Process.spawn(loop, args[0], args, {
    redirect: [stdout, stderr],
    onExit: (_, _, _) -> exited = true
  }) {
    case Ok(process): cb -> {
      // process.kill results in "Uncaught exception Cannot call null"
      if (!exited)
        switch Process.killPid(process.pid(), SIGKILL) {
          case Ok(_):
          case Error(e): fail('Could not end run command', e);
        }
      process.close(cb);
    }
    case Error(e): 
      Sys.stderr().writeString('Could not run "$command", because $e');
      cb -> cb();
  }
}

function createBuild(port: Int, config: BuildConfig, done: (hasError: Bool) -> Void, retry = 0) {
  if (retry > 1000) fail('Could not connect to port $port');
  switch [
    SockAddr.ipv4('127.0.0.1', port), 
    Tcp.init(loop)
  ] {
    case [Ok(addr), Ok(socket)]:
      socket.connect(addr, res -> 
        switch res {
          case Ok(_):
            var hasError = false;
            socket.readStart(res -> switch res {
              case Ok(_.toString() => data):
                for (line in data.split('\n')) {
                  switch (line.charCodeAt(0)) {
                    case 0x01:
                      Sys.print(line.substr(1).split('\x01').join('\n'));
                    case 0x02:
                      hasError = true;
                    default:
                      if (line.length > 0) {
                        Sys.stderr().writeString(line + '\n');
                        Sys.stderr().flush();
                      }
                  }
                }
              case Error(UV_EOF): 
                socket.close(() -> done(hasError));
              case Error(e):
                fail('Server closed', e);
            });
            socket.write([config.arguments.join('\n') + '\000'], (res, bytesWritten) -> switch res {
              case Ok(_):
              case Error(e): fail('Could not write to server', e);
            });
          case Error(UV_ECONNREFUSED):
            socket.close(() -> createBuild(port, config, done, retry + 1));
          case Error(e): 
            fail('Could not connect to server', e);
        }
      );
    case [_, Error(e)] | [Error(e), _]:
      fail('Could not connect to server', e);
  }
}

function formatDuration(duration: Float) {
  if (duration < 1000)
    return '${Math.round(duration)}ms';
  final precision = 100;
  final s = Math.round(duration / 1000 * precision) / precision;
  return '${s}s';
}

function getFreePort(done: (port: haxe.ds.Option<Int>) -> Void) {
  return switch [
    SockAddr.ipv4('127.0.0.1', 0),
    Tcp.init(loop)
  ] {
    case [Ok(addr), Ok(socket)]:
      switch socket.bind(addr) {
        case Ok(_): 
          switch socket.getSockName() {
            case Ok(addr): 
              socket.close(() -> done(Some(addr.port)));
            default: 
              socket.close(() -> done(None));
          }
        default: done(None);
      }
    default: done(None);
  }
}

function register() {
  function getPort(done: (port: Int) -> Void) {
    switch Context.definedValue('watch.port') {
      case null: 
        getFreePort(res -> 
          switch res {
            case Some(port): done(port);
            default: fail('Could not find free port');
          }
        );
      case v: done(Std.parseInt(v));
    }
  }
  getPort(port -> {
    final config = buildArguments(Sys.args());
    final excludes = config.excludes.map(FileSystem.absolutePath);
    final includes = config.includes.map(FileSystem.absolutePath);
    final classPaths = 
      Context.getClassPath().map(FileSystem.absolutePath)
        .filter(path -> {
          final isRoot = path == FileSystem.absolutePath('.');
          if (Context.defined('watch.excludeRoot') && isRoot) return false;
          return !excludes.contains(path);
        });
    final paths = dedupePaths(classPaths.concat(includes));
    createServer(port, server -> {
      var next: Timer;
      var building = false;
      var closeRun = cb -> cb();
      function build() {
        switch Timer.init(loop) {
          case Ok(timer):
            if (next != null) {
              next.stop();
            }
            next = timer;
            timer.start(() -> {
              if (building) {
                build();
                return;
              }
              building = true;
              final start = Sys.time();
              if (Context.defined('watch.verbose'))
                Sys.println('\x1b[32m> Build started\x1b[39m');
              server.build(config, (hasError: Bool) -> {
                building = false;
                final duration = (Sys.time() - start) * 1000;
                closeRun(() -> {
                  closeRun = cb -> cb();
                  timer.close(() -> {
                    if (Context.defined('watch.verbose')) {
                      final status = if (hasError) 31 else 32;
                      Sys.println('\x1b[${status}m> Build finished\x1b[39m');
                    }
                    if (hasError) {
                      Sys.println('\x1b[90m> Found errors\x1b[39m');
                    } else { 
                      Sys.println('\x1b[36m> Build completed in ${formatDuration(duration)}\x1b[39m');
                      switch Context.definedValue('watch.run') {
                        case null:
                        case v: closeRun = runCommand(v);
                      }
                    }
                  });
                });
              });
            }, 100);
          case Error(e): fail('Could not init time', e);
        }
      }
      function watch() {
        for (path in paths) {
          switch FsEvent.init(loop) {
            case Ok(watcher):
              watcher.start(path, [
                FsEventFlag.FS_EVENT_RECURSIVE
              ], res ->
                switch res {
                  case Ok({file: (_.toString()) => file}):
                    if (StringTools.endsWith(file, '.hx')) {
                      for (exclude in excludes) {
                        if (isSubOf(FileSystem.absolutePath(file), exclude)) 
                          return;
                      }
                      build();
                    }
                  case Error(e):
                }
              );
            case Error(e): fail('Could not watch $path', e); 
          }
        }
      }
      build();
      watch();
    });
  });
  loop.loop();
}
