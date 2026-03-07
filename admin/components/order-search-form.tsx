export default function OrderSearchForm({ initialValue = '' }: { initialValue?: string }) {
  return (
    <form method="GET" action="/orders" className="flex items-center gap-2">
      <input
        type="search"
        name="q"
        defaultValue={initialValue}
        placeholder="Order #, email, or deal..."
        className="px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent min-w-[180px]"
      />
      <button
        type="submit"
        className="px-4 py-2 text-sm font-medium rounded-lg bg-gray-900 text-white hover:bg-gray-800 transition-colors"
      >
        Search
      </button>
    </form>
  )
}
