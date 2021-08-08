package watch;

import eval.NativeString;
import eval.luv.Timer;
import eval.luv.FsEvent;
import eval.luv.Process;
import eval.luv.SockAddr;
import eval.luv.Tcp;
import haxe.macro.Context;
import sys.FileSystem;

final loop = sys.thread.Thread.current().events;

function fail(message: String, ?error: Dynamic) {
  Sys.println(message);
  if (error != null) 
    Sys.print('$error');
  Sys.exit(1);
}

function buildArguments() {
  final args = Sys.args();
  final forward = [];
  var i = 0;
  function skip() i++;
  while (i < args.length) {
    switch [args[i], args[i + 1]] {
      case 
        ['-L' | '-lib' | '--library', 'watch'],
        ['--macro', 'watch.Watch.register()']:
        skip();
      default:
        forward.push(args[i]);
    }
    skip();
  }
  return forward;
}

typedef Server = {
  build: (config: Array<String>, done: (hasError: Bool) -> Void) -> Void,
  close: (done: () -> Void) -> Void
}

function createServer(port: Int, cb: (server: Server) -> Void) {
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

function runCommand(command: String) {
  // I have no clue how this stuff should actually be split
  final args = command.split(' ').map(_ -> (_: NativeString));
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

function createBuild(port: Int, config: Array<String>, done: (hasError: Bool) -> Void, retry = 0) {
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
            socket.write([config.join('\n') + '\000'], (res, bytesWritten) -> switch res {
              case Ok(_):
              case Error(e): fail('Could not write to server', e);
            });
          case Error(UV_ECONNREFUSED):
            socket.close(() -> createBuild(port, config, done, retry++));
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

function register() {
  final port = 45612;
  final paths = Context.getClassPath();
  final config = buildArguments();
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
            server.build(config, (hasError: Bool) -> {
              building = false;
              final duration = (Sys.time() - start) * 1000;
              closeRun(() -> {
                closeRun = cb -> cb();
                timer.close(() -> {
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
            watcher.start(FileSystem.absolutePath(path), [
              FsEventFlag.FS_EVENT_RECURSIVE
            ], res -> 
              switch res {
                case Ok({file: (_.toString()) => file}):
                  if (StringTools.endsWith(file, '.hx'))
                    build();
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
  loop.loop();
}