package tests;

import watch.Watch.dedupePaths;
import watch.Watch.isSubOf;
import watch.Watch.buildArguments;

final testArguments = suite(test -> {
  test('append parameters to options that require it', () -> 
    assert.equal(
      buildArguments(['-lib', 'a']).arguments,
      ['-lib a']
    )
  );

  test('do not append to options that do not require input', () -> 
    assert.equal(
      buildArguments(['-debug', 'path']).arguments,
      ['-debug', 'path']
    )
  );

  test('example setup', () -> 
    assert.equal(
      buildArguments(
        ['-js', 'bin/test.js', '--next', '-php', 'bin/php', '--each', '--cmd', 'echo ok']
      ).arguments,
      ['-js bin/test.js', '--next', '-php bin/php', '--each', '--cmd echo ok']
    )
  );

  
  test('get excludes', () -> 
    assert.equal(
      buildArguments(['-D', 'watch.exclude=a', '-D', 'watch.exclude=b']),
      {arguments: [], excludes: ['a', 'b']}
    )
  );
});

final testSub = suite(test -> {
  test('check separators', () -> {
    assert.ok(isSubOf('c:\\a\\b', 'c:/a'));
  });
});

final testDedupe = suite(test -> {
  test('dedupe', () -> {
    assert.equal(
      dedupePaths(['/project', '/project/src']),
      ['/project']
    );
    assert.equal(
      dedupePaths(['/project/src', '/project']),
      ['/project']
    );
  });
});