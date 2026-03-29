'use client'

import { useRouter } from 'next/navigation'
import { useState, useTransition, type FormEvent } from 'react'
import { toast } from 'sonner'
import {
  createUserBillingAddress,
  deleteUserBillingAddress,
  setDefaultUserBillingAddress,
  updateUserBillingAddress,
  type BillingAddressFormValues,
} from '@/app/actions/user-billing-addresses'

export type BillingAddressRow = {
  id: string
  user_id: string
  label: string
  address_line1: string
  address_line2: string
  city: string
  state: string
  postal_code: string
  country: string
  is_default: boolean
  created_at: string
  updated_at: string
}

const emptyForm: BillingAddressFormValues = {
  label: '',
  address_line1: '',
  address_line2: '',
  city: '',
  state: '',
  postal_code: '',
  country: 'US',
  is_default: false,
}

function rowToForm(r: BillingAddressRow): BillingAddressFormValues {
  return {
    label: r.label ?? '',
    address_line1: r.address_line1 ?? '',
    address_line2: r.address_line2 ?? '',
    city: r.city ?? '',
    state: r.state ?? '',
    postal_code: r.postal_code ?? '',
    country: r.country ?? 'US',
    is_default: !!r.is_default,
  }
}

export default function UserBillingAddressesPanel({
  userId,
  addresses,
}: {
  userId: string
  addresses: BillingAddressRow[]
}) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [showAdd, setShowAdd] = useState(false)
  const [addForm, setAddForm] = useState<BillingAddressFormValues>({ ...emptyForm, is_default: addresses.length === 0 })
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editForm, setEditForm] = useState<BillingAddressFormValues>(emptyForm)

  const refresh = () => router.refresh()

  const onCreate = (e: FormEvent) => {
    e.preventDefault()
    startTransition(async () => {
      try {
        await createUserBillingAddress(userId, addForm)
        toast.success('Address added')
        setAddForm({ ...emptyForm, is_default: false })
        setShowAdd(false)
        refresh()
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Failed to add address')
      }
    })
  }

  const onUpdate = (addressId: string, e: FormEvent) => {
    e.preventDefault()
    startTransition(async () => {
      try {
        await updateUserBillingAddress(userId, addressId, editForm)
        toast.success('Address updated')
        setEditingId(null)
        refresh()
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Failed to update')
      }
    })
  }

  const onDelete = (addressId: string) => {
    if (!window.confirm('Delete this address?')) return
    startTransition(async () => {
      try {
        await deleteUserBillingAddress(userId, addressId)
        toast.success('Address deleted')
        if (editingId === addressId) setEditingId(null)
        refresh()
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Failed to delete')
      }
    })
  }

  const onSetDefault = (addressId: string) => {
    startTransition(async () => {
      try {
        await setDefaultUserBillingAddress(userId, addressId)
        toast.success('Default address updated')
        refresh()
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Failed to set default')
      }
    })
  }

  const startEdit = (r: BillingAddressRow) => {
    setEditingId(r.id)
    setEditForm(rowToForm(r))
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-base font-semibold text-gray-900">Billing addresses</h2>
        <button
          type="button"
          onClick={() => {
            if (showAdd) {
              setShowAdd(false)
            } else {
              setEditingId(null)
              setAddForm({ ...emptyForm, is_default: addresses.length === 0 })
              setShowAdd(true)
            }
          }}
          className="text-sm font-medium text-blue-600 hover:text-blue-800"
        >
          {showAdd ? 'Cancel add' : '+ Add address'}
        </button>
      </div>
      <p className="mt-1 text-xs text-gray-500">
        Manage saved billing / shipping addresses for checkout. One default per user.
      </p>

      {showAdd && (
        <form onSubmit={onCreate} className="mt-4 space-y-3 rounded-lg border border-gray-100 bg-gray-50 p-4">
          <p className="text-sm font-medium text-gray-800">New address</p>
          <AddressFields form={addForm} onChange={setAddForm} disabled={isPending} />
          <button
            type="submit"
            disabled={isPending}
            className="rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-800 disabled:opacity-50"
          >
            Save address
          </button>
        </form>
      )}

      <ul className="mt-4 space-y-3">
        {addresses.length === 0 && !showAdd && (
          <li className="text-sm text-gray-500">No addresses yet.</li>
        )}
        {addresses.map((row) => (
          <li key={row.id} className="rounded-lg border border-gray-200 p-4">
            {editingId === row.id ? (
              <form onSubmit={(e) => onUpdate(row.id, e)} className="space-y-3">
                <AddressFields form={editForm} onChange={setEditForm} disabled={isPending} />
                <div className="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    disabled={isPending}
                    className="rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800 disabled:opacity-50"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    disabled={isPending}
                    onClick={() => setEditingId(null)}
                    className="rounded-lg border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            ) : (
              <>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-medium text-gray-900">{row.label || 'Unnamed'}</span>
                      {row.is_default && (
                        <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-800">
                          Default
                        </span>
                      )}
                    </div>
                    <p className="mt-1 text-sm text-gray-700">
                      {row.address_line1}
                      {row.address_line2 ? `, ${row.address_line2}` : ''}
                    </p>
                    <p className="text-sm text-gray-600">
                      {[row.city, row.state, row.postal_code].filter(Boolean).join(', ')} · {row.country}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {!row.is_default && (
                      <button
                        type="button"
                        disabled={isPending}
                        onClick={() => onSetDefault(row.id)}
                        className="rounded-md border border-gray-300 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                      >
                        Set default
                      </button>
                    )}
                    <button
                      type="button"
                      disabled={isPending}
                      onClick={() => startEdit(row)}
                      className="rounded-md border border-gray-300 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      disabled={isPending}
                      onClick={() => onDelete(row.id)}
                      className="rounded-md border border-red-200 px-2 py-1 text-xs font-medium text-red-700 hover:bg-red-50 disabled:opacity-50"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function AddressFields({
  form,
  onChange,
  disabled,
}: {
  form: BillingAddressFormValues
  onChange: (f: BillingAddressFormValues) => void
  disabled: boolean
}) {
  const set = (patch: Partial<BillingAddressFormValues>) => onChange({ ...form, ...patch })

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      <label className="sm:col-span-2 block text-xs font-medium text-gray-600">
        Label
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.label}
          onChange={(e) => set({ label: e.target.value })}
          disabled={disabled}
          placeholder="Home, Office…"
        />
      </label>
      <label className="sm:col-span-2 block text-xs font-medium text-gray-600">
        Address line 1 <span className="text-red-500">*</span>
        <input
          required
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.address_line1}
          onChange={(e) => set({ address_line1: e.target.value })}
          disabled={disabled}
        />
      </label>
      <label className="sm:col-span-2 block text-xs font-medium text-gray-600">
        Address line 2
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.address_line2}
          onChange={(e) => set({ address_line2: e.target.value })}
          disabled={disabled}
        />
      </label>
      <label className="block text-xs font-medium text-gray-600">
        City
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.city}
          onChange={(e) => set({ city: e.target.value })}
          disabled={disabled}
        />
      </label>
      <label className="block text-xs font-medium text-gray-600">
        State
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.state}
          onChange={(e) => set({ state: e.target.value })}
          disabled={disabled}
        />
      </label>
      <label className="block text-xs font-medium text-gray-600">
        Postal code
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.postal_code}
          onChange={(e) => set({ postal_code: e.target.value })}
          disabled={disabled}
        />
      </label>
      <label className="block text-xs font-medium text-gray-600">
        Country
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={form.country}
          onChange={(e) => set({ country: e.target.value })}
          disabled={disabled}
          placeholder="US"
        />
      </label>
      <label className="sm:col-span-2 flex items-center gap-2 text-xs font-medium text-gray-700">
        <input
          type="checkbox"
          checked={form.is_default}
          onChange={(e) => set({ is_default: e.target.checked })}
          disabled={disabled}
        />
        Set as default address
      </label>
    </div>
  )
}
