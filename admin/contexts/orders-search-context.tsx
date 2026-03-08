'use client'

import { createContext, useContext, useState, useCallback, type ReactNode } from 'react'

type OrdersSearchContextValue = {
  isSearching: boolean
  setSearching: (v: boolean) => void
}

const OrdersSearchContext = createContext<OrdersSearchContextValue | null>(null)

export function OrdersSearchProvider({ children }: { children: ReactNode }) {
  const [isSearching, setSearching] = useState(false)
  const value: OrdersSearchContextValue = {
    isSearching,
    setSearching: useCallback((v: boolean) => setSearching(v), []),
  }
  return (
    <OrdersSearchContext.Provider value={value}>
      {children}
    </OrdersSearchContext.Provider>
  )
}

export function useOrdersSearch() {
  const ctx = useContext(OrdersSearchContext)
  return ctx
}
