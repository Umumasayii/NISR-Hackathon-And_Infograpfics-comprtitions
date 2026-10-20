import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// base './' keeps every path relative, so the same build works on GitHub Pages
// (https://<user>.github.io/<repo>/), on Netlify or from any folder.
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['logo.svg', 'icons/*.png', 'topojson/*.json'],
      manifest: {
        name: 'SmartIrrigate Rwanda',
        short_name: 'SmartIrrigate',
        description: 'Where small-scale irrigation is needed in Rwanda, who irrigates and how harvests compare. Powered by Team NiyoIshimwe.',
        theme_color: '#176B45',
        background_color: '#F7F9F6',
        display: 'standalone',
        start_url: './',
        scope: './',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // the data files and the chart library are cached too, so the app opens offline
        globPatterns: ['**/*.{js,css,html,svg,png,json,md,woff2}'],
        maximumFileSizeToCacheInBytes: 8 * 1024 * 1024,
      },
    }),
  ],
  build: { chunkSizeWarningLimit: 5000 },
});
