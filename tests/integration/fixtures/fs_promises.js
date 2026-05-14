const fsp = require('fs/promises');
const fs = require('fs');

async function main() {
  const tmpDir = '/tmp/dun_fsp_test_' + Date.now();
  const tmpFile = tmpDir + '/test.txt';

  // 1. require('fs/promises') works
  console.log('PASS: require fs/promises: ' + (typeof fsp.readFile === 'function'));

  // 2. require('fs').promises works
  console.log('PASS: fs.promises: ' + (typeof fs.promises.readFile === 'function'));

  // 3. mkdir
  await fsp.mkdir(tmpDir);
  console.log('PASS: mkdir created dir');

  // 4. writeFile
  await fsp.writeFile(tmpFile, 'hello async');
  console.log('PASS: writeFile completed');

  // 5. readFile
  const content = await fsp.readFile(tmpFile);
  console.log('PASS: readFile: ' + (content === 'hello async'));

  // 6. appendFile
  await fsp.appendFile(tmpFile, ' world');
  const content2 = await fsp.readFile(tmpFile);
  console.log('PASS: appendFile: ' + (content2 === 'hello async world'));

  // 7. stat
  const st = await fsp.stat(tmpFile);
  console.log('PASS: stat isFile: ' + st.isFile());
  console.log('PASS: stat size: ' + (st.size > 0));

  // 8. copyFile
  const copyPath = tmpDir + '/copy.txt';
  await fsp.copyFile(tmpFile, copyPath);
  const copyContent = await fsp.readFile(copyPath);
  console.log('PASS: copyFile: ' + (copyContent === 'hello async world'));

  // 9. readdir
  const entries = await fsp.readdir(tmpDir);
  const sorted = entries.sort();
  console.log('PASS: readdir: ' + sorted.join(','));

  // 10. rename
  const renamedPath = tmpDir + '/renamed.txt';
  await fsp.rename(copyPath, renamedPath);
  const renamedExists = require('fs').existsSync(renamedPath);
  console.log('PASS: rename: ' + renamedExists);

  // 11. access (should not throw for existing file)
  await fsp.access(tmpFile);
  console.log('PASS: access ok');

  // 12. access (should throw for missing file)
  try {
    await fsp.access('/no/such/file/xyz');
    console.log('FAIL: access should throw');
  } catch (e) {
    console.log('PASS: access throws for missing: true');
  }

  // 13. realpath
  const real = await fsp.realpath(tmpFile);
  console.log('PASS: realpath: ' + (real.length > 0));

  // 14. chmod
  await fsp.chmod(tmpFile, 0o644);
  console.log('PASS: chmod ok');

  // 15. lstat
  const lst = await fsp.lstat(tmpFile);
  console.log('PASS: lstat isFile: ' + lst.isFile());

  // 16. truncate
  await fsp.truncate(tmpFile, 5);
  const truncContent = await fsp.readFile(tmpFile);
  console.log('PASS: truncate: ' + (truncContent === 'hello'));

  // 17. unlink
  await fsp.unlink(tmpFile);
  await fsp.unlink(renamedPath);
  console.log('PASS: unlink ok');

  // 18. rmdir
  await fsp.rmdir(tmpDir);
  console.log('PASS: rmdir ok');

  // 19. mkdir recursive + rm recursive
  const deepDir = '/tmp/dun_fsp_deep_' + Date.now() + '/a/b/c';
  await fsp.mkdir(deepDir, { recursive: true });
  await fsp.writeFile(deepDir + '/file.txt', 'deep');
  const deepContent = await fsp.readFile(deepDir + '/file.txt');
  console.log('PASS: mkdir recursive: ' + (deepContent === 'deep'));
  const baseDeep = '/tmp/dun_fsp_deep_' + deepDir.split('dun_fsp_deep_')[1].split('/')[0];
  await fsp.rm(baseDeep, { recursive: true });
  console.log('PASS: rm recursive ok');

  // 20. symlink
  const symlinkDir = '/tmp/dun_fsp_sym_' + Date.now();
  await fsp.mkdir(symlinkDir);
  const symlinkTarget = symlinkDir + '/target.txt';
  const symlinkPath = symlinkDir + '/link.txt';
  await fsp.writeFile(symlinkTarget, 'symlink content');
  await fsp.symlink(symlinkTarget, symlinkPath);
  const symlinkContent = await fsp.readFile(symlinkPath);
  console.log('PASS: symlink: ' + (symlinkContent === 'symlink content'));
  const symlinkStat = await fsp.lstat(symlinkPath);
  console.log('PASS: symlink isSymbolicLink: ' + symlinkStat.isSymbolicLink());
  await fsp.rm(symlinkDir, { recursive: true });

  // 21. rm with force (should not throw for missing file)
  try {
    await fsp.rm('/tmp/dun_nonexistent_' + Date.now(), { force: true });
    console.log('PASS: rm force no throw: true');
  } catch (e) {
    console.log('FAIL: rm force should not throw');
  }

  // 22. open returns FileHandle
  const openDir = '/tmp/dun_fsp_open_' + Date.now();
  await fsp.mkdir(openDir);
  const openFile = openDir + '/fh_test.txt';
  await fsp.writeFile(openFile, 'filehandle content');

  const fh = await fsp.open(openFile, 'r');
  console.log('PASS: open returns FileHandle: ' + (typeof fh.fd === 'number'));
  console.log('PASS: FileHandle has close: ' + (typeof fh.close === 'function'));
  console.log('PASS: FileHandle has stat: ' + (typeof fh.stat === 'function'));
  console.log('PASS: FileHandle has read: ' + (typeof fh.read === 'function'));

  // 23. FileHandle readFile
  const fhContent = await fh.readFile('utf8');
  console.log('PASS: FileHandle readFile: ' + (fhContent === 'filehandle content'));

  // 24. FileHandle stat
  const fhStat = await fh.stat();
  console.log('PASS: FileHandle stat isFile: ' + fhStat.isFile());

  // 25. FileHandle close
  await fh.close();
  console.log('PASS: FileHandle close ok');

  // 26. FileHandle write mode
  const writeFile = openDir + '/fh_write.txt';
  const fhw = await fsp.open(writeFile, 'w');
  await fhw.writeFile('written via fh');
  await fhw.close();
  const writtenContent = await fsp.readFile(writeFile);
  console.log('PASS: FileHandle writeFile: ' + (writtenContent === 'written via fh'));

  // cleanup
  await fsp.rm(openDir, { recursive: true, force: true });

  console.log('All fs/promises tests passed');
}

main().catch(e => {
  console.log('ERROR: ' + e.message);
  process.exit(1);
});
