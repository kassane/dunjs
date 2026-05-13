// Test WebSocket API availability
const ws = require('ws');
console.log('ws module: ' + (typeof ws === 'object'));
console.log('WebSocketServer: ' + (typeof ws.WebSocketServer === 'function'));
console.log('WebSocket class: ' + (typeof ws.WebSocket === 'function'));

// WebSocket constructor via module
var WS = ws.WebSocket;
console.log('ws constructor: ' + (typeof WS === 'function'));

console.log('ws done');
