
const config = require('../src/config/env');
console.log('--- Environment Debug ---');
console.log('Port:', config.port);
console.log('Node Env:', config.nodeEnv);
console.log('Firebird Host:', config.firebird.host);
console.log('Firebird Database:', config.firebird.database);
console.log('Firebird User:', config.firebird.user ? 'OK (DEFINED)' : 'UNDEFINED');
console.log('Firebird Password:', config.firebird.password ? 'OK (DEFINED)' : 'UNDEFINED');
console.log('Mock Mode:', config.firebird.mock);
console.log('-------------------------');
if (!config.firebird.user || !config.firebird.password) {
    console.error('CRITICAL: User or Password not defined in config!');
    process.exit(1);
}
console.log('Config looks good.');
