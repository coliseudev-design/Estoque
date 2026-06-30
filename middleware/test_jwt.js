const jwt = require('jsonwebtoken');

const secret = 'Coliseu2026!IdentitySuperSecretKeyOauth20';
// Simulating C# GenerateToken which sets aud and iss
const token = jwt.sign({ tenantId: '123' }, secret, { audience: 'coliseu-speed-api', issuer: 'coliseu-identity-device', expiresIn: '30m' });

try {
    const decoded = jwt.verify(token, secret);
    console.log('SUCCESS:', decoded);
} catch (e) {
    console.log('ERROR:', e.name, e.message);
}
