// Real-world: Async task runner with microtask priorities and error handling
const tasks = [];
const results = [];

function addTask(name, priority, fn) {
  tasks.push({ name, priority, fn });
}

function runTasks() {
  // Sort by priority (lower = first)
  tasks.sort(function(a, b) { return a.priority - b.priority; });

  // Run each task, collecting results via microtask queue
  const promises = tasks.map(function(task) {
    return new Promise(function(resolve, reject) {
      queueMicrotask(function() {
        try {
          const result = task.fn();
          results.push({ name: task.name, status: 'ok', result: result });
          resolve(result);
        } catch (e) {
          results.push({ name: task.name, status: 'error', result: e.message });
          resolve(null);
        }
      });
    });
  });

  return Promise.all(promises);
}

// Register tasks with different priorities
addTask('validate', 1, function() {
  const data = { users: ['alice', 'bob', 'charlie'] };
  if (!Array.isArray(data.users)) throw new Error('invalid data');
  return data.users.length;
});

addTask('transform', 2, function() {
  const items = [3, 1, 4, 1, 5, 9, 2, 6];
  const unique = items.filter(function(v, i, a) { return a.indexOf(v) === i; });
  unique.sort(function(a, b) { return a - b; });
  return unique.join(',');
});

addTask('failing_task', 3, function() {
  throw new Error('intentional failure');
});

addTask('compute', 4, function() {
  // Fibonacci via closure
  const fib = (function() {
    const cache = {};
    return function f(n) {
      if (n in cache) return cache[n];
      if (n <= 1) return n;
      cache[n] = f(n - 1) + f(n - 2);
      return cache[n];
    };
  })();
  return fib(20);
});

runTasks().then(function() {
  console.log('tasks: ' + results.length);
  results.forEach(function(r) {
    console.log(r.name + ': ' + r.status + ' -> ' + r.result);
  });
});
