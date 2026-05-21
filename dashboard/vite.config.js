import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const apiProxyTarget = process.env.VITE_API_PROXY_TARGET || 'http://localhost:3000'
const wsProxyTarget = apiProxyTarget.replace(/^http/, 'ws')

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: false,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      },
      '/health': {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      },
      '/version': {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      },
      '/ws': {
        target: wsProxyTarget,
        ws: true,
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          charts: ['recharts'],
          motion: ['framer-motion']
        }
      }
    }
  }
})
