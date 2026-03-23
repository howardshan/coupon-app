'use client'

import { createContext, useContext } from 'react'

const OrdersSearchContext = createContext({})

export function OrdersSearchProvider({ children }: { children: React.ReactNode }) {
  return (
    <OrdersSearchContext.Provider value={{}}>
      {children}
    </OrdersSearchContext.Provider>
  )
}

export function useOrdersSearch() {
  return useContext(OrdersSearchContext)
}
