import { ref, onMounted, onUnmounted } from 'vue'

export interface ZoomState {
  isOpen: boolean
  imageSrc: string
  imageAlt: string
  caption?: string
}

const zoomState = ref<ZoomState>({
  isOpen: false,
  imageSrc: '',
  imageAlt: '',
  caption: undefined
})

export function useDiagramZoom() {
  const openZoom = (src: string, alt: string, caption?: string) => {
    zoomState.value = {
      isOpen: true,
      imageSrc: src,
      imageAlt: alt,
      caption
    }
  }

  const closeZoom = () => {
    zoomState.value.isOpen = false
  }

  // Setup click handlers for zoomable diagrams
  const setupZoomHandlers = () => {
    const handleDiagramClick = (e: Event) => {
      const target = e.target as HTMLElement
      
      // Check if clicked element is a zoomable diagram
      if (target.tagName === 'IMG' && target.classList.contains('diagram')) {
        const figure = target.closest('.diagram-container')
        if (!figure) return
        
        // Check if diagram has aria-describedby (indicates it's zoomable)
        const ariaDescribedBy = target.getAttribute('aria-describedby')
        if (!ariaDescribedBy) return
        
        const src = target.getAttribute('src')
        const alt = target.getAttribute('alt')
        const figcaption = figure.querySelector('figcaption')
        const caption = figcaption?.textContent || undefined
        
        if (src && alt) {
          openZoom(src, alt, caption)
        }
      }
    }

    document.addEventListener('click', handleDiagramClick)
    
    return () => {
      document.removeEventListener('click', handleDiagramClick)
    }
  }

  return {
    zoomState,
    openZoom,
    closeZoom,
    setupZoomHandlers
  }
}
