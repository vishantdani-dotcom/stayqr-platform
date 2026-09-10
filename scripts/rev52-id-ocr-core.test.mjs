import assert from 'node:assert/strict'
import {
  candidateFromAzure,
  candidateFromText,
  finalizeCandidates,
  isValidAadhaar,
} from '../supabase/functions/_shared/idOcrCore.js'

let checks = 0
function test(name, fn) {
  fn()
  checks += 1
  console.log(`PASS ${String(checks).padStart(2, '0')} ${name}`)
}

test('synthetic Aadhaar checksum is validated', () => {
  assert.equal(isValidAadhaar('123456789010'), true)
  assert.equal(isValidAadhaar('123456789011'), false)
})

const aadhaarText = `Government of India\nAADHAAR\nUPENDRA MANI TIWARI\nDOB: 21/02/1992\nMale\nAddress: 12 Test Nagar, Nagpur, Maharashtra 440009\n1234 5678 9010`
const aadhaarGoogle = candidateFromText('google-vision', aadhaarText, 'auto', 0.8)

test('Aadhaar parser extracts name DOB address and validated masked number', () => {
  assert.equal(aadhaarGoogle.documentType, 'aadhaar')
  assert.equal(aadhaarGoogle.extractedFields.full_name, 'Upendra Mani Tiwari')
  assert.equal(aadhaarGoogle.extractedFields.date_of_birth, '1992-02-21')
  assert.equal(aadhaarGoogle.documentNumberValid, true)
  assert.equal(aadhaarGoogle.documentNumberMasked, 'XXXX XXXX 9010')
})

const aadhaarAzure = candidateFromAzure({
  analyzeResult: {
    content: aadhaarText,
    documents: [{
      docType: 'idDocument',
      confidence: 0.96,
      fields: {
        FirstName: { valueString: 'UPENDRA MANI', confidence: 0.97 },
        LastName: { valueString: 'TIWARI', confidence: 0.97 },
        DateOfBirth: { valueDate: '1992-02-21', confidence: 0.98 },
        Sex: { valueString: 'M', confidence: 0.98 },
        DocumentNumber: { valueString: '123456789010', confidence: 0.98 },
        Address: { content: '12 Test Nagar, Nagpur, Maharashtra 440009', confidence: 0.91 },
        CountryRegion: { valueCountryRegion: 'IND', confidence: 0.99 },
      },
    }],
  },
}, 'auto')

test('Azure structured Aadhaar result maps into StayQR fields', () => {
  assert.equal(aadhaarAzure.structured, true)
  assert.equal(aadhaarAzure.extractedFields.full_name, 'Upendra Mani Tiwari')
  assert.equal(aadhaarAzure.documentNumberValid, true)
})

test('structured Aadhaar reaches strong extracted result', () => {
  const result = finalizeCandidates([aadhaarAzure], 'auto')
  assert.equal(result.status, 'extracted')
  assert.equal(result.reviewRequired, false)
  assert.equal(result.identityConsensus, 'strong')
  assert.equal(result.providerStructured, true)
})

test('two agreeing OCR providers produce strong consensus', () => {
  const ocr2 = candidateFromText('ocr-space', aadhaarText.replace('UPENDRA MANI TIWARI', 'Upendra Mani Tiwari'), 'auto', 0.6)
  const result = finalizeCandidates([aadhaarGoogle, ocr2], 'auto')
  assert.equal(result.identityConsensus, 'strong')
  assert.equal(result.status, 'extracted')
})

test('conflicting OCR identities fail closed', () => {
  const otherText = aadhaarText.replace('UPENDRA MANI TIWARI', 'AVNISH KUMAR')
  const other = candidateFromText('ocr-space', otherText, 'auto', 0.65)
  const result = finalizeCandidates([aadhaarGoogle, other], 'auto')
  assert.equal(result.identityConsensus, 'low')
  assert.equal(result.reviewRequired, true)
})

test('invalid Aadhaar checksum is never returned as a valid ID number', () => {
  const bad = candidateFromText('google-vision', aadhaarText.replace('1234 5678 9010', '1234 5678 9011'), 'auto', 0.8)
  assert.equal(bad.documentNumberValid, false)
  assert.equal(bad.documentNumberMasked, '')
})

const panText = `INCOME TAX DEPARTMENT\nGOVT. OF INDIA\nUPENDRA MANI TIWARI\nDOB: 21/02/1992\nPermanent Account Number\nABCDE1234F`

test('PAN parser validates PAN format and identity fields', () => {
  const pan = candidateFromText('google-vision', panText, 'auto', 0.8)
  assert.equal(pan.documentType, 'pan')
  assert.equal(pan.documentNumberValid, true)
  assert.equal(pan.extractedFields.full_name, 'Upendra Mani Tiwari')
})

const passportText = `REPUBLIC OF INDIA\nPASSPORT\nSurname\nTIWARI\nGiven Name\nUPENDRA MANI\nDOB 21/02/1992\nP<INDTIWARI<<UPENDRA<MANI<<<<<<<<<<<<<<<<<<<<\nA12345678IND9202219M3001012<<<<<<<<<<<<<<00`

test('passport MRZ path extracts a plausible identity', () => {
  const passport = candidateFromText('google-vision', passportText, 'auto', 0.8)
  assert.equal(passport.documentType, 'passport')
  assert.ok(passport.extractedFields.full_name.toLowerCase().includes('upendra'))
})

console.log(JSON.stringify({ checks, passed: checks, failed: 0 }))
