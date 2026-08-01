import { loadTenantContext } from './tenantContext'

/**
 * Return the hotel selected by the canonical authenticated tenant context.
 *
 * No page is allowed to invent, hard-code or silently fall back to a tenant.
 * A null result means the signed-in user has no authorized hotel context.
 */
export async function getCurrentHotel() {
  try {
    const context = await loadTenantContext()
    return context?.selectedHotel || null
  } catch (error) {
    console.error('Current hotel context error:', error)
    return null
  }
}
