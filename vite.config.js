import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function stayqrVendorChunk(moduleId) {
  const id = moduleId.replaceAll('\\', '/')

  if (!id.includes('/node_modules/')) return undefined

  if (
    id.includes('/react/') ||
    id.includes('/react-dom/') ||
    id.includes('/scheduler/')
  ) {
    return 'vendor-react'
  }

  if (id.includes('/@supabase/')) {
    return 'vendor-supabase'
  }

  if (id.includes('/@dnd-kit/')) {
    return 'vendor-dnd'
  }

  if (
    id.includes('/jspdf/') ||
    id.includes('/html2canvas/') ||
    id.includes('/dompurify/')
  ) {
    return 'vendor-documents'
  }

  return 'vendor'
}

export default defineConfig({
  plugins: [react()],
  build: {
    cssCodeSplit: true,
    manifest: true,
    reportCompressedSize: true,
    chunkSizeWarningLimit: 650,
    rollupOptions: {
      output: {
        manualChunks: stayqrVendorChunk,
      },
    },
  },
})
