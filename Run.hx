function main() {
  // Some day we could parse hxml files and extract class paths here,
  // which would allow us to watch and restart on hxml file changes
  final args = Sys.args();
  Sys.setCwd(args.pop());
  Sys.exit(Sys.command('haxe -lib watch ${args.join(' ')}'));
}