// Class features (inspired by Bun class tests / Deno class_test.ts)

class Animal {
    constructor(name) {
        this.name = name;
    }
    speak() {
        return `${this.name} makes a noise`;
    }
}

class Dog extends Animal {
    speak() {
        return `${this.name} barks`;
    }
}

const d = new Dog("Rex");
console.log(d.speak());
console.log(d instanceof Dog);
console.log(d instanceof Animal);

// Static methods
class MathUtil {
    static add(a, b) { return a + b; }
    static #secret = 42;
    static getSecret() { return MathUtil.#secret; }
}
console.log(MathUtil.add(3, 4));
console.log(MathUtil.getSecret());

// Private fields
class Counter {
    #count = 0;
    increment() { this.#count++; }
    get value() { return this.#count; }
}
const counter = new Counter();
counter.increment();
counter.increment();
console.log(counter.value);

// Computed property names
const prop = "dynamic";
const obj = {
    [prop]: true,
    [`${prop}2`]: false,
};
console.log(obj.dynamic);
console.log(obj.dynamic2);

// toString / valueOf
class Temperature {
    constructor(celsius) { this.celsius = celsius; }
    valueOf() { return this.celsius; }
    toString() { return `${this.celsius}°C`; }
}
const t = new Temperature(100);
console.log(`${t}`);
console.log(t + 0);
