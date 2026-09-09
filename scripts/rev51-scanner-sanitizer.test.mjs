import assert from 'node:assert/strict'
import { sanitizeProviderIdentityAnalysis } from '../src/lib/idDocumentIntelligence.js'

const base = {
  documentType: 'aadhaar',
  documentNumberMasked: 'XXXX XXXX 6767',
  status: 'extracted',
  qualityScore: 95,
  reviewRequired: false,
  qualityReasons: [],
  extractedFields: {
    date_of_birth: '2002-02-21',
    gender: 'male',
    nationality: 'India',
    address_line1: 'Dighori, Nagpur',
  },
}

function sample(name) {
  return {...base, extractedFields: {...base.extractedFields, full_name: name}}
}

const signature = sanitizeProviderIdentityAnalysis(sample('Signat'), 'WhatsApp Image 2026-09-06.jpeg')
assert.equal(signature.autoFillAllowed, false)
assert.deepEqual(signature.extractedFields, {})
assert.equal(signature.documentNumberMasked, null)
assert.equal(signature.reviewRequired, true)

const mismatch = sanitizeProviderIdentityAnalysis(sample('Avnish Kumar'), 'Upendra Mani Tiwari.jpg')
assert.equal(mismatch.autoFillAllowed, false)
assert.deepEqual(mismatch.extractedFields, {})
assert.equal(mismatch.documentNumberMasked, null)

const good = sanitizeProviderIdentityAnalysis(sample('Upendra Mani Tiwari'), 'Upendra Mani Tiwari.jpg')
assert.equal(good.autoFillAllowed, true)
assert.equal(good.extractedFields.full_name, 'Upendra Mani Tiwari')
assert.equal(good.documentNumberMasked, 'XXXX XXXX 6767')

console.log('REV51 scanner sanitizer: 3/3 PASS')
