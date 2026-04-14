'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import {
  addServiceArea,
  updateServiceArea,
  deleteServiceArea,
  addCityToMetro,
} from './actions'

type ServiceArea = {
  id: string
  level: string
  state_name: string
  metro_name: string | null
  city_name: string | null
  sort_order: number
  is_active: boolean
  created_at: string
  updated_at: string
}

type UnmatchedCity = {
  city: string
  merchantCount: number
}

// 构建树形结构
type CityNode = { id: string; name: string; sortOrder: number }
type MetroNode = { id: string; name: string; sortOrder: number; cities: CityNode[] }
type StateNode = { id: string; name: string; sortOrder: number; metros: MetroNode[] }

function buildTree(areas: ServiceArea[]): StateNode[] {
  const stateMap = new Map<string, StateNode>()
  const metroMap = new Map<string, MetroNode>()

  // state 级别
  for (const a of areas) {
    if (a.level === 'state') {
      stateMap.set(a.state_name, {
        id: a.id,
        name: a.state_name,
        sortOrder: a.sort_order,
        metros: [],
      })
    }
  }

  // metro 级别
  for (const a of areas) {
    if (a.level === 'metro' && a.metro_name) {
      const key = `${a.state_name}::${a.metro_name}`
      const metro: MetroNode = {
        id: a.id,
        name: a.metro_name,
        sortOrder: a.sort_order,
        cities: [],
      }
      metroMap.set(key, metro)

      // 挂载到 state
      let state = stateMap.get(a.state_name)
      if (!state) {
        state = { id: '', name: a.state_name, sortOrder: 0, metros: [] }
        stateMap.set(a.state_name, state)
      }
      state.metros.push(metro)
    }
  }

  // city 级别
  for (const a of areas) {
    if (a.level === 'city' && a.metro_name && a.city_name) {
      const key = `${a.state_name}::${a.metro_name}`
      const metro = metroMap.get(key)
      if (metro) {
        metro.cities.push({
          id: a.id,
          name: a.city_name,
          sortOrder: a.sort_order,
        })
      }
    }
  }

  // 排序
  const states = [...stateMap.values()].sort((a, b) => a.sortOrder - b.sortOrder)
  for (const s of states) {
    s.metros.sort((a, b) => a.sortOrder - b.sortOrder)
    for (const m of s.metros) {
      m.cities.sort((a, b) => a.sortOrder - b.sortOrder)
    }
  }
  return states
}

export default function RegionsClient({
  initialAreas,
  unmatchedCities,
}: {
  initialAreas: ServiceArea[]
  unmatchedCities: UnmatchedCity[]
}) {
  const [isPending, startTransition] = useTransition()
  const tree = buildTree(initialAreas)

  // 展开/折叠状态
  const [expandedStates, setExpandedStates] = useState<Set<string>>(
    new Set(tree.map(s => s.name))
  )
  const [expandedMetros, setExpandedMetros] = useState<Set<string>>(
    new Set(tree.flatMap(s => s.metros.map(m => `${s.name}::${m.name}`)))
  )

  // 添加表单
  const [addMode, setAddMode] = useState<'state' | 'metro' | 'city' | null>(null)
  const [addParentState, setAddParentState] = useState('')
  const [addParentMetro, setAddParentMetro] = useState('')
  const [addName, setAddName] = useState('')

  // 编辑
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')

  // 一键添加的 metro 选择
  const [quickAddMetros, setQuickAddMetros] = useState<Record<string, string>>({})

  // 收集所有 metros 用于一键添加的下拉
  const allMetros = tree.flatMap(s =>
    s.metros.map(m => ({ state: s.name, metro: m.name }))
  )

  function toggleState(name: string) {
    setExpandedStates(prev => {
      const next = new Set(prev)
      next.has(name) ? next.delete(name) : next.add(name)
      return next
    })
  }

  function toggleMetro(key: string) {
    setExpandedMetros(prev => {
      const next = new Set(prev)
      next.has(key) ? next.delete(key) : next.add(key)
      return next
    })
  }

  function handleAdd() {
    if (!addName.trim()) return
    startTransition(async () => {
      try {
        if (addMode === 'state') {
          await addServiceArea('state', addName, null, null, 0)
        } else if (addMode === 'metro') {
          await addServiceArea('metro', addParentState, addName, null, 0)
        } else if (addMode === 'city') {
          await addServiceArea('city', addParentState, addParentMetro, addName, 0)
        }
        toast.success(`Added "${addName}"`)
        setAddMode(null)
        setAddName('')
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Failed to add')
      }
    })
  }

  function handleSaveEdit(id: string, level: string) {
    if (!editName.trim()) return
    const updates: Record<string, string> = {}
    if (level === 'state') updates.state_name = editName.trim()
    else if (level === 'metro') updates.metro_name = editName.trim()
    else updates.city_name = editName.trim()

    startTransition(async () => {
      try {
        await updateServiceArea(id, updates)
        toast.success('Updated')
        setEditingId(null)
        setEditName('')
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Failed to update')
      }
    })
  }

  function handleDelete(id: string, name: string) {
    if (!confirm(`Delete "${name}"? This cannot be undone.`)) return
    startTransition(async () => {
      try {
        await deleteServiceArea(id)
        toast.success(`Deleted "${name}"`)
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Failed to delete')
      }
    })
  }

  function handleQuickAdd(city: string) {
    const metroKey = quickAddMetros[city]
    if (!metroKey) {
      toast.error('Please select a metro area first')
      return
    }
    const [stateName, metroName] = metroKey.split('::')
    startTransition(async () => {
      try {
        await addCityToMetro(city, metroName, stateName)
        toast.success(`Added "${city}" to ${metroName}`)
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Failed to add')
      }
    })
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Region Management</h1>

      {isPending && (
        <div className="mb-4 text-sm text-blue-600">Updating…</div>
      )}

      {/* ── 未匹配城市警告 ── */}
      {unmatchedCities.length > 0 && (
        <div className="bg-amber-50 border border-amber-300 rounded-xl p-5 mb-6">
          <h2 className="text-base font-semibold text-amber-800 mb-1">
            Unmatched Cities
          </h2>
          <p className="text-sm text-amber-700 mb-4">
            These cities exist in merchant data but are not in the service area list.
            Users won&apos;t see deals from these cities until they are added.
          </p>
          <div className="space-y-3">
            {unmatchedCities.map(({ city, merchantCount }) => (
              <div
                key={city}
                className="flex items-center gap-3 bg-white rounded-lg px-4 py-3 border border-amber-200"
              >
                <div className="flex-1">
                  <span className="font-medium text-gray-900">{city}</span>
                  <span className="ml-2 text-xs text-gray-500">
                    ({merchantCount} merchant{merchantCount > 1 ? 's' : ''})
                  </span>
                </div>
                <select
                  value={quickAddMetros[city] ?? ''}
                  onChange={e =>
                    setQuickAddMetros(prev => ({ ...prev, [city]: e.target.value }))
                  }
                  className="px-2 py-1.5 border border-gray-300 rounded-lg bg-white text-sm min-w-[140px]"
                >
                  <option value="">Select metro</option>
                  {allMetros.map(m => (
                    <option key={`${m.state}::${m.metro}`} value={`${m.state}::${m.metro}`}>
                      {m.metro} ({m.state})
                    </option>
                  ))}
                </select>
                <button
                  onClick={() => handleQuickAdd(city)}
                  disabled={isPending || !quickAddMetros[city]}
                  className="px-3 py-1.5 bg-amber-600 text-white rounded-lg text-sm font-medium hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Quick Add
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── 添加区域 ── */}
      <div className="bg-white rounded-xl border border-gray-200 p-5 mb-6">
        {addMode === null ? (
          <div className="flex items-center gap-3">
            <span className="text-sm font-semibold text-gray-700">Add:</span>
            <button
              onClick={() => setAddMode('state')}
              className="px-3 py-1.5 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200"
            >
              + State
            </button>
            <button
              onClick={() => {
                setAddMode('metro')
                if (tree.length > 0) setAddParentState(tree[0].name)
              }}
              className="px-3 py-1.5 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200"
            >
              + Metro
            </button>
            <button
              onClick={() => {
                setAddMode('city')
                if (tree.length > 0) {
                  setAddParentState(tree[0].name)
                  if (tree[0].metros.length > 0) setAddParentMetro(tree[0].metros[0].name)
                }
              }}
              className="px-3 py-1.5 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200"
            >
              + City
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <span className="text-sm font-semibold text-gray-700">
                Add {addMode === 'state' ? 'State' : addMode === 'metro' ? 'Metro' : 'City'}
              </span>
              <button
                onClick={() => { setAddMode(null); setAddName('') }}
                className="text-xs text-gray-500 hover:underline"
              >
                Cancel
              </button>
            </div>
            <div className="flex items-end gap-3 flex-wrap">
              {/* 父级选择 */}
              {(addMode === 'metro' || addMode === 'city') && (
                <label className="flex flex-col gap-1">
                  <span className="text-xs text-gray-500">State</span>
                  <select
                    value={addParentState}
                    onChange={e => {
                      setAddParentState(e.target.value)
                      const s = tree.find(s => s.name === e.target.value)
                      if (s && s.metros.length > 0) setAddParentMetro(s.metros[0].name)
                    }}
                    className="px-3 py-2 border border-gray-300 rounded-lg bg-white text-sm"
                  >
                    {tree.map(s => (
                      <option key={s.name} value={s.name}>{s.name}</option>
                    ))}
                  </select>
                </label>
              )}
              {addMode === 'city' && (
                <label className="flex flex-col gap-1">
                  <span className="text-xs text-gray-500">Metro</span>
                  <select
                    value={addParentMetro}
                    onChange={e => setAddParentMetro(e.target.value)}
                    className="px-3 py-2 border border-gray-300 rounded-lg bg-white text-sm"
                  >
                    {tree
                      .find(s => s.name === addParentState)
                      ?.metros.map(m => (
                        <option key={m.name} value={m.name}>{m.name}</option>
                      ))}
                  </select>
                </label>
              )}
              <label className="flex flex-col gap-1">
                <span className="text-xs text-gray-500">Name</span>
                <input
                  type="text"
                  value={addName}
                  onChange={e => setAddName(e.target.value)}
                  placeholder={
                    addMode === 'state' ? 'e.g. California'
                      : addMode === 'metro' ? 'e.g. San Antonio'
                      : 'e.g. San Marcos'
                  }
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm min-w-[200px]"
                  onKeyDown={e => e.key === 'Enter' && handleAdd()}
                />
              </label>
              <button
                onClick={handleAdd}
                disabled={isPending || !addName.trim()}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Add
              </button>
            </div>
          </div>
        )}
      </div>

      {/* ── 地区树 ── */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h2 className="text-base font-semibold text-gray-800">Service Area Tree</h2>
          <p className="text-xs text-gray-500 mt-0.5">
            Manage the State → Metro → City hierarchy visible to users.
          </p>
        </div>

        {tree.length === 0 ? (
          <div className="px-4 py-8 text-center text-gray-400">
            No service areas configured yet
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {tree.map(state => (
              <div key={state.id || state.name}>
                {/* State 行 */}
                <div className="flex items-center gap-2 px-4 py-3 bg-gray-50 hover:bg-gray-100">
                  <button
                    onClick={() => toggleState(state.name)}
                    className="text-gray-400 hover:text-gray-600 w-5"
                  >
                    {expandedStates.has(state.name) ? '▾' : '▸'}
                  </button>
                  <span className="text-lg">🏛️</span>
                  {editingId === state.id ? (
                    <div className="flex items-center gap-2 flex-1">
                      <input
                        type="text"
                        value={editName}
                        onChange={e => setEditName(e.target.value)}
                        className="px-2 py-1 border border-gray-300 rounded text-sm"
                        autoFocus
                        onKeyDown={e => e.key === 'Enter' && handleSaveEdit(state.id, 'state')}
                      />
                      <button onClick={() => handleSaveEdit(state.id, 'state')} className="text-xs text-blue-600 hover:underline">Save</button>
                      <button onClick={() => setEditingId(null)} className="text-xs text-gray-500 hover:underline">Cancel</button>
                    </div>
                  ) : (
                    <>
                      <span className="font-semibold text-gray-900 flex-1">{state.name}</span>
                      <span className="text-xs text-gray-400">
                        {state.metros.length} metro{state.metros.length !== 1 ? 's' : ''}
                      </span>
                      <button
                        onClick={() => { setEditingId(state.id); setEditName(state.name) }}
                        className="text-xs text-blue-600 hover:underline"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleDelete(state.id, state.name)}
                        disabled={isPending}
                        className="text-xs text-red-600 hover:underline disabled:opacity-50"
                      >
                        Delete
                      </button>
                    </>
                  )}
                </div>

                {/* Metros */}
                {expandedStates.has(state.name) && state.metros.map(metro => {
                  const metroKey = `${state.name}::${metro.name}`
                  return (
                    <div key={metro.id}>
                      {/* Metro 行 */}
                      <div className="flex items-center gap-2 px-4 py-2.5 pl-10 hover:bg-gray-50">
                        <button
                          onClick={() => toggleMetro(metroKey)}
                          className="text-gray-400 hover:text-gray-600 w-5"
                        >
                          {expandedMetros.has(metroKey) ? '▾' : '▸'}
                        </button>
                        <span className="text-base">📍</span>
                        {editingId === metro.id ? (
                          <div className="flex items-center gap-2 flex-1">
                            <input
                              type="text"
                              value={editName}
                              onChange={e => setEditName(e.target.value)}
                              className="px-2 py-1 border border-gray-300 rounded text-sm"
                              autoFocus
                              onKeyDown={e => e.key === 'Enter' && handleSaveEdit(metro.id, 'metro')}
                            />
                            <button onClick={() => handleSaveEdit(metro.id, 'metro')} className="text-xs text-blue-600 hover:underline">Save</button>
                            <button onClick={() => setEditingId(null)} className="text-xs text-gray-500 hover:underline">Cancel</button>
                          </div>
                        ) : (
                          <>
                            <span className="font-medium text-gray-800 flex-1">{metro.name}</span>
                            <span className="text-xs text-gray-400">
                              {metro.cities.length} cit{metro.cities.length !== 1 ? 'ies' : 'y'}
                            </span>
                            <button
                              onClick={() => { setEditingId(metro.id); setEditName(metro.name) }}
                              className="text-xs text-blue-600 hover:underline"
                            >
                              Edit
                            </button>
                            <button
                              onClick={() => handleDelete(metro.id, metro.name)}
                              disabled={isPending}
                              className="text-xs text-red-600 hover:underline disabled:opacity-50"
                            >
                              Delete
                            </button>
                          </>
                        )}
                      </div>

                      {/* Cities */}
                      {expandedMetros.has(metroKey) && metro.cities.map(city => (
                        <div
                          key={city.id}
                          className="flex items-center gap-2 px-4 py-2 pl-20 hover:bg-gray-50"
                        >
                          <span className="text-sm text-gray-400">•</span>
                          {editingId === city.id ? (
                            <div className="flex items-center gap-2 flex-1">
                              <input
                                type="text"
                                value={editName}
                                onChange={e => setEditName(e.target.value)}
                                className="px-2 py-1 border border-gray-300 rounded text-sm"
                                autoFocus
                                onKeyDown={e => e.key === 'Enter' && handleSaveEdit(city.id, 'city')}
                              />
                              <button onClick={() => handleSaveEdit(city.id, 'city')} className="text-xs text-blue-600 hover:underline">Save</button>
                              <button onClick={() => setEditingId(null)} className="text-xs text-gray-500 hover:underline">Cancel</button>
                            </div>
                          ) : (
                            <>
                              <span className="text-gray-700 flex-1">{city.name}</span>
                              <button
                                onClick={() => { setEditingId(city.id); setEditName(city.name) }}
                                className="text-xs text-blue-600 hover:underline"
                              >
                                Edit
                              </button>
                              <button
                                onClick={() => handleDelete(city.id, city.name)}
                                disabled={isPending}
                                className="text-xs text-red-600 hover:underline disabled:opacity-50"
                              >
                                Delete
                              </button>
                            </>
                          )}
                        </div>
                      ))}
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
