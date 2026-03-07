// https://vitepress.dev/guide/custom-theme
import { h } from 'vue'
import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import './style.css'
import DiagramZoom from './components/DiagramZoom.vue'
import MermaidDiagram from './components/MermaidDiagram.vue'
import { useDiagramZoom } from './composables/useDiagramZoom'

export default {
  extends: DefaultTheme,
  Layout: () => {
    const { zoomState, closeZoom } = useDiagramZoom()
    
    return h(DefaultTheme.Layout, null, {
      // Add diagram zoom modal to layout
      'layout-bottom': () => h(DiagramZoom, {
        isOpen: zoomState.value.isOpen,
        imageSrc: zoomState.value.imageSrc,
        imageAlt: zoomState.value.imageAlt,
        caption: zoomState.value.caption,
        onClose: closeZoom
      })
    })
  },
  enhanceApp({ app }) {
    app.component('MermaidDiagram', MermaidDiagram)

    // Setup diagram zoom handlers when app is mounted
    if (typeof window !== 'undefined') {
      const { setupZoomHandlers } = useDiagramZoom()
      
      // Setup handlers after a short delay to ensure DOM is ready
      setTimeout(() => {
        setupZoomHandlers()
      }, 100)
    }
  }
} satisfies Theme
