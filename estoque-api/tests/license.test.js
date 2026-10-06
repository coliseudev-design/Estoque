'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { generateKeyCandidates } = require('../src/auth/license');

test('generateKeyCandidates handles visual similarity 5 and S', () => {
    const candidates = generateKeyCandidates('COL-KGYZ-FXUY-5FHQ');
    assert.ok(candidates.includes('COL-KGYZ-FXUY-5FHQ'));
    assert.ok(candidates.includes('COL-KGYZ-FXUY-SFHQ'));
});

test('generateKeyCandidates handles visual similarity S and 5', () => {
    const candidates = generateKeyCandidates('COL-KGYZ-FXUY-SFHQ');
    assert.ok(candidates.includes('COL-KGYZ-FXUY-SFHQ'));
    assert.ok(candidates.includes('COL-KGYZ-FXUY-5FHQ'));
});

test('generateKeyCandidates normalizes missing COL- prefix', () => {
    const candidates = generateKeyCandidates('KGYZ-FXUY-SFHQ');
    assert.ok(candidates.includes('COL-KGYZ-FXUY-SFHQ'));
});

test('generateKeyCandidates formats unhyphenated keys', () => {
    const candidates = generateKeyCandidates('COLKGYZFXUYSFHQ');
    assert.ok(candidates.includes('COL-KGYZ-FXUY-SFHQ'));
});
