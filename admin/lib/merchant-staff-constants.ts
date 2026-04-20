/**
 * 门店店员角色 — 与 DB merchant_staff_role_check 一致。
 * 放在独立文件（非 'use server'），供 Client Components 与 Server Actions 共用。
 */

export const MERCHANT_STAFF_ROLES = [
  'cashier',
  'service',
  'manager',
  'finance',
  'regional_manager',
  'trainee',
] as const

export type MerchantStaffRole = (typeof MERCHANT_STAFF_ROLES)[number]
