import { apiClient } from './client'

export async function downloadBasic() {
  const blob = await apiClient.get<Blob>('/api/v1/downloads/basic', {
    responseType: 'blob',
  })
  triggerDownload(blob, 'ai9_build_basic.zip')
}

export async function downloadFull() {
  const blob = await apiClient.get<Blob>('/api/v1/downloads/full', {
    responseType: 'blob',
  })
  triggerDownload(blob, 'ai9_build_full.zip')
}

function triggerDownload(blob: Blob, filename: string) {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.setAttribute('download', filename)
  document.body.appendChild(link)
  link.click()
  link.parentNode?.removeChild(link)
  window.URL.revokeObjectURL(url)
}
