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

  console.log('All fs/promises tests passed');
}

main().catch(e => {
  console.log('ERROR: ' + e.message);
  process.exit(1);
});
