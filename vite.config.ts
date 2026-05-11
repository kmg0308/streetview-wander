import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { randomStreetViewApi } from './server/randomStreetViewApi'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), randomStreetViewApi()],
})
