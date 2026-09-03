import { existsSync } from 'node:fs'
import { join, resolve } from 'node:path'

const requiredFiles = ['stayqr.in_current.html', 'DEPLOY_stayqr.in/index.html']

export function resolveMarketingRoot(sourceRoot, configuredRoot = '', exists = existsSync) {
  const override = String(configuredRoot).trim()
  // Explicit configuration always wins. Defaults cover the original sibling
  // layout and this workspace's existing Post-Launch Batch A source bundle.
  // Never choose another copy based on whether its content passes validation.
  const candidates = override
    ? [resolve(override)]
    : [
        resolve(sourceRoot, '..', 'marketing'),
        resolve(sourceRoot, '..', '..', '10_POSTLAUNCH_BATCH_A', 'Marketing_BATCH_A'),
      ]
  const selected = override ? candidates[0] : candidates.find((candidate) => exists(candidate))
  if (!selected) {
    throw new Error(`Marketing source not found. Set STAYQR_MARKETING_ROOT to the intended source directory. Checked: ${candidates.join('; ')}`)
  }
  const missing = requiredFiles.filter((file) => !exists(join(selected, file)))
  if (missing.length) {
    throw new Error(`Marketing source is incomplete at ${selected}. Required file(s) missing: ${missing.join(', ')}. No fallback was used; check STAYQR_MARKETING_ROOT.`)
  }
  return selected
}
