import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],

  server: {
    port: 5173,
    proxy: {
      // Forward all /api HTTP requests to FastAPI
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
      // Forward WebSocket connections (/api/ws/...) to FastAPI
      '/api/ws': {
        target:  'ws://127.0.0.1:8000',
        ws:      true,
        changeOrigin: true,
      },
    },
  },
})
