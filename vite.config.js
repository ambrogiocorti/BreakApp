import { defineConfig } from 'vite';

export default defineConfig({
  base: process.env.GITHUB_PAGES_BASE || '/',
  server: {
    host: '127.0.0.1',
    // The managed preview forwards requests through this local hostname.
    allowedHosts: ['terminal.local'],
    port: 5173,
    strictPort: true
  },
  preview: {
    host: '127.0.0.1',
    port: 4173
  },
  build: {
    outDir: 'dist',
    sourcemap: false
  }
});
