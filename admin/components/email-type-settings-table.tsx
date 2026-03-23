'use client'

import { useState } from 'react'
import { toggleEmailGlobalEnabled, updateAdminRecipients } from '@/app/actions/email-settings'

interface EmailTypeSetting {
  id: string
  email_code: string
  email_name: string
  recipient_type: 'customer' | 'merchant' | 'admin'
  global_enabled: boolean
  user_configurable: boolean
  admin_recipient_emails: string[]
  description: string | null
  updated_at: string
}

interface Props {
  settings: EmailTypeSetting[]
}

// 每个分组的颜色主题
const GROUP_STYLE = {
  customer: { badge: 'bg-blue-100 text-blue-700',  header: 'text-blue-700',  label: 'Customer' },
  merchant: { badge: 'bg-purple-100 text-purple-700', header: 'text-purple-700', label: 'Merchant' },
  admin:    { badge: 'bg-orange-100 text-orange-700', header: 'text-orange-700', label: 'Admin' },
}

export default function EmailTypeSettingsTable({ settings }: Props) {
  // 按 recipient_type 分组
  const grouped: Record<string, EmailTypeSetting[]> = {
    customer: settings.filter(s => s.recipient_type === 'customer'),
    merchant: settings.filter(s => s.recipient_type === 'merchant'),
    admin:    settings.filter(s => s.recipient_type === 'admin'),
  }

  return (
    <div className="space-y-8">
      {(['customer', 'merchant', 'admin'] as const).map(type => (
        <div key={type}>
          {/* 分组标题 */}
          <h2 className={`text-sm font-semibold uppercase tracking-wide mb-3 ${GROUP_STYLE[type].header}`}>
            {GROUP_STYLE[type].label} Emails ({grouped[type].length})
          </h2>

          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="text-left px-4 py-3 font-medium text-gray-600 w-16">Code</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Email Name</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600 w-36">User Can Toggle</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600 w-32">Global Switch</th>
                  {type === 'admin' && (
                    <th className="text-left px-4 py-3 font-medium text-gray-600">Recipients</th>
                  )}
                  <th className="text-left px-4 py-3 font-medium text-gray-600 w-36">Last Updated</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {grouped[type].map(setting => (
                  <EmailTypeRow key={setting.email_code} setting={setting} showRecipients={type === 'admin'} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ))}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// 单行组件
// ─────────────────────────────────────────────────────────────

function EmailTypeRow({
  setting,
  showRecipients,
}: {
  setting: EmailTypeSetting
  showRecipients: boolean
}) {
  const [toggling, setToggling] = useState(false)
  const [editingRecipients, setEditingRecipients] = useState(false)
  const [recipientInput, setRecipientInput] = useState(
    setting.admin_recipient_emails.join('\n')
  )
  const [savingRecipients, setSavingRecipients] = useState(false)

  async function handleToggle() {
    setToggling(true)
    try {
      await toggleEmailGlobalEnabled(setting.email_code, !setting.global_enabled)
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Failed to update')
    } finally {
      setToggling(false)
    }
  }

  async function handleSaveRecipients() {
    setSavingRecipients(true)
    try {
      const emails = recipientInput
        .split('\n')
        .map(e => e.trim())
        .filter(Boolean)
      await updateAdminRecipients(setting.email_code, emails)
      setEditingRecipients(false)
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Failed to save recipients')
    } finally {
      setSavingRecipients(false)
    }
  }

  return (
    <tr className={`hover:bg-gray-50/50 ${!setting.global_enabled ? 'opacity-60' : ''}`}>
      {/* 邮件编码 */}
      <td className="px-4 py-3">
        <span className="font-mono text-xs font-semibold text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded">
          {setting.email_code}
        </span>
      </td>

      {/* 邮件名称 */}
      <td className="px-4 py-3">
        <span className="font-medium text-gray-900">{setting.email_name}</span>
        {setting.description && (
          <p className="text-xs text-gray-400 mt-0.5">{setting.description}</p>
        )}
      </td>

      {/* 用户可自主关闭？ */}
      <td className="px-4 py-3">
        {setting.user_configurable ? (
          <span className="inline-flex items-center gap-1 text-xs text-green-700 bg-green-50 border border-green-200 px-2 py-0.5 rounded-full">
            <span className="w-1.5 h-1.5 rounded-full bg-green-500" />
            User can toggle
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 text-xs text-gray-500 bg-gray-50 border border-gray-200 px-2 py-0.5 rounded-full">
            <span className="w-1.5 h-1.5 rounded-full bg-gray-400" />
            Mandatory
          </span>
        )}
      </td>

      {/* 全局开关 */}
      <td className="px-4 py-3">
        <button
          onClick={handleToggle}
          disabled={toggling}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors disabled:opacity-50 focus:outline-none ${
            setting.global_enabled ? 'bg-green-500' : 'bg-gray-300'
          }`}
          title={setting.global_enabled ? 'Click to disable' : 'Click to enable'}
        >
          <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
            setting.global_enabled ? 'translate-x-6' : 'translate-x-1'
          }`} />
        </button>
        <span className={`ml-2 text-xs font-medium ${setting.global_enabled ? 'text-green-600' : 'text-gray-400'}`}>
          {toggling ? '...' : setting.global_enabled ? 'On' : 'Off'}
        </span>
      </td>

      {/* 管理员收件人（仅 A 系列） */}
      {showRecipients && (
        <td className="px-4 py-3">
          {editingRecipients ? (
            <div className="flex flex-col gap-2">
              <textarea
                value={recipientInput}
                onChange={e => setRecipientInput(e.target.value)}
                placeholder="One email per line"
                rows={3}
                className="text-xs border border-gray-300 rounded px-2 py-1 w-full focus:outline-none focus:ring-1 focus:ring-blue-400 resize-none"
              />
              <div className="flex gap-2">
                <button
                  onClick={handleSaveRecipients}
                  disabled={savingRecipients}
                  className="text-xs bg-blue-600 text-white px-2 py-1 rounded hover:bg-blue-700 disabled:opacity-50"
                >
                  {savingRecipients ? 'Saving...' : 'Save'}
                </button>
                <button
                  onClick={() => {
                    setEditingRecipients(false)
                    setRecipientInput(setting.admin_recipient_emails.join('\n'))
                  }}
                  className="text-xs text-gray-500 hover:text-gray-700 px-2 py-1"
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <div
              className="group cursor-pointer"
              onClick={() => setEditingRecipients(true)}
            >
              {setting.admin_recipient_emails.length > 0 ? (
                <div className="flex flex-col gap-0.5">
                  {setting.admin_recipient_emails.map(email => (
                    <span key={email} className="text-xs text-gray-600 truncate max-w-[180px]">
                      {email}
                    </span>
                  ))}
                </div>
              ) : (
                <span className="text-xs text-gray-400 italic">No recipients</span>
              )}
              <span className="text-xs text-blue-500 opacity-0 group-hover:opacity-100 mt-0.5 block">
                Click to edit
              </span>
            </div>
          )}
        </td>
      )}

      {/* 最后更新时间 */}
      <td className="px-4 py-3 text-xs text-gray-400">
        {new Date(setting.updated_at).toLocaleDateString('en-US', {
          month: 'short', day: 'numeric', year: 'numeric',
        })}
      </td>
    </tr>
  )
}
