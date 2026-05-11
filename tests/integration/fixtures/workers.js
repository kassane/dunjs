const w = new Worker(__dirname + '/workers_worker.js');
w.onmessage = (e) => {
    console.log('sum:', e.data.result);
};
w.postMessage({ n: 10 });
