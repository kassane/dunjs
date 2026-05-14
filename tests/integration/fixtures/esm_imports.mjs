import { join } from 'path'
import { dirname } from 'node:path'
import { existsSync } from 'dun:fs'
import { basename } from "dun:path"
import { createHash } from "crypto"

console.log(join('a', 'b'))
console.log(dirname('/foo/bar.js'))
console.log(existsSync('/tmp'))
console.log(basename('/x/y/z.txt'))
console.log(createHash('md5').update('test').digest('hex').length)
