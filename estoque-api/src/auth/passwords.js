/**
 * Hash de senhas e PINs com scrypt (node:crypto) — sem dependência nativa.
 * Formato: scrypt$<salt base64>$<hash base64>
 */
'use strict';

const crypto = require('node:crypto');
const { promisify } = require('node:util');

const scrypt = promisify(crypto.scrypt);
const KEYLEN = 32;

async function hashSecret(plain) {
    const salt = crypto.randomBytes(16);
    const hash = await scrypt(String(plain), salt, KEYLEN);
    return `scrypt$${salt.toString('base64')}$${hash.toString('base64')}`;
}

async function verifySecret(plain, stored) {
    if (!stored || !stored.startsWith('scrypt$')) return false;
    const [, saltB64, hashB64] = stored.split('$');
    const expected = Buffer.from(hashB64, 'base64');
    const actual = await scrypt(String(plain), Buffer.from(saltB64, 'base64'), expected.length);
    return crypto.timingSafeEqual(actual, expected);
}

module.exports = { hashSecret, verifySecret };
