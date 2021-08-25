package tests;

import watch.Watch.dedupePaths;
import watch.Watch.isSubOf;
import watch.Watch.buildArguments;

final testArguments = suite(test -> {
  test('append parameters to options that require it', () -> 
    assert.equal(
      buildArguments(['-lib', 'a']),
      ['-lib a']
    )
  );

  test('do not append to options that do not require input', () -> 
    assert.equal(
      buildArguments(['-debug', 'path']),
      ['-debug', 'path']
    )
  );

  test('example setup', () -> 
    assert.equal(
      buildArguments(
        ['-js', 'bin/test.js', '--next', '-php', 'bin/php', '--each', '--cmd', 'echo ok']
      ),
      ['-js bin/test.js', '--next', '-php bin/php', '--each', '--cmd echo ok']
    )
  );
});

final testSub = suite(test -> {
  test('check separators', () -> {
    assert.ok(isSubOf('c:\\a\\b', 'C:/a'));
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