self.onmessage = (e) => {
    const n = e.data.n;
    let sum = 0;
    for (let i = 1; i <= n; i++) sum += i;
    self.postMessage({ result: sum });
};
