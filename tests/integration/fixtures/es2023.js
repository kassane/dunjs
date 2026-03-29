// Test ES2023 features supported by QuickJS-NG

// Array.prototype.findLast
const arr = [1, 2, 3, 4, 5];
console.log(arr.findLast(x => x < 4)); // 3

// Array.prototype.findLastIndex
console.log(arr.findLastIndex(x => x < 4)); // 2

// Array.prototype.toReversed (immutable)
const reversed = arr.toReversed();
console.log(reversed.join(",")); // "5,4,3,2,1"
console.log(arr.join(","));     // "1,2,3,4,5" (unchanged)

// Array.prototype.toSorted (immutable)
const unsorted = [3, 1, 4, 1, 5];
const sorted = unsorted.toSorted();
console.log(sorted.join(","));    // "1,1,3,4,5"
console.log(unsorted.join(",")); // "3,1,4,1,5" (unchanged)

// Object.groupBy
const inventory = [
    { name: "asparagus", type: "vegetables" },
    { name: "bananas", type: "fruit" },
    { name: "cherries", type: "fruit" },
];
const grouped = Object.groupBy(inventory, item => item.type);
console.log(Object.keys(grouped).sort().join(",")); // "fruit,vegetables"
