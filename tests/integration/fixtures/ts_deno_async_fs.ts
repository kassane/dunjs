// Deno async file-system APIs: mkdir / stat / lstat / rename /
// copyFile / remove / readDir (AsyncIterable) and the text/binary
// file helpers. All shim on top of their *Sync companions and wrap
// in Promise (or AsyncIterable for readDir).

const tmp = `/tmp/dun_deno_async_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

await Deno.mkdir(tmp);
await Deno.writeTextFile(`${tmp}/a.txt`, "hello");
console.log("read async:", await Deno.readTextFile(`${tmp}/a.txt`));
console.log("stat size:", (await Deno.stat(`${tmp}/a.txt`)).size);
await Deno.rename(`${tmp}/a.txt`, `${tmp}/b.txt`);
console.log("rename ok:", (await Deno.stat(`${tmp}/b.txt`)).size);
await Deno.copyFile(`${tmp}/b.txt`, `${tmp}/c.txt`);
console.log("copy ok:", (await Deno.stat(`${tmp}/c.txt`)).size);

const names: string[] = [];
for await (const entry of Deno.readDir(tmp)) {
    names.push(entry.name);
}
names.sort();
console.log("readDir:", names.join(","));

console.log("lstat is_file:", (await Deno.lstat(`${tmp}/b.txt`)).isFile);

await Deno.remove(`${tmp}/b.txt`);
await Deno.remove(`${tmp}/c.txt`);
Deno.removeSync(tmp);
console.log("cleanup ok");
