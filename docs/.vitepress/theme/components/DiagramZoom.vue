<template>
  <Teleport to="body">
    <Transition name="zoom-modal">
      <div
        v-if="isOpen"
        class="diagram-zoom-modal"
        @click="close"
        @keydown.esc="close"
        role="dialog"
        aria-modal="true"
        aria-label="Zoomed diagram view"
        tabindex="-1"
      >
        <div class="zoom-modal-content" @click.stop>
          <button
            class="zoom-close-button"
            @click="close"
            aria-label="Close zoomed view"
            title="Close (Esc)"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
          </button>
          <img
            :src="imageSrc"
            :alt="imageAlt"
            class="zoomed-diagram"
            @load="onImageLoad"
          />
          <div v-if="caption" class="zoom-caption">{{ caption }}</div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from 'vue'

const props = defineProps<{
  isOpen: boolean
  imageSrc: string
  imageAlt: string
  caption?: string
}>()

const emit = defineEmits<{
  close: []
}>()

const close = () => {
  emit('close')
}

const onImageLoad = () => {
  // Focus the modal for keyboard navigation
  const modal = document.querySelector('.diagram-zoom-modal') as HTMLElement
  if (modal) {
    modal.focus()
  }
}

// Handle escape key
const handleEscape = (e: KeyboardEvent) => {
  if (e.key === 'Escape' && props.isOpen) {
    close()
  }
}

// Prevent body scroll when modal is open
watch(() => props.isOpen, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden'
  } else {
    document.body.style.overflow = ''
  }
})

onMounted(() => {
  document.addEventListener('keydown', handleEscape)
})

onUnmounted(() => {
  document.removeEventListener('keydown', handleEscape)
  document.body.style.overflow = ''
})
</script>

<style scoped>
.diagram-zoom-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.9);
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2rem;
  cursor: zoom-out;
}

.zoom-modal-content {
  position: relative;
  max-width: 95vw;
  max-height: 95vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  cursor: default;
}

.zoomed-diagram {
  max-width: 100%;
  max-height: 85vh;
  object-fit: contain;
  border-radius: 8px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
}

.zoom-close-button {
  position: absolute;
  top: -3rem;
  right: 0;
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 50%;
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: white;
  transition: all 0.2s ease;
}

.zoom-close-button:hover {
  background: rgba(255, 255, 255, 0.2);
  transform: scale(1.1);
}

.zoom-close-button:focus {
  outline: 2px solid white;
  outline-offset: 2px;
}

.zoom-caption {
  margin-top: 1rem;
  color: rgba(255, 255, 255, 0.9);
  font-size: 0.95rem;
  text-align: center;
  max-width: 600px;
}

/* Transition animations */
.zoom-modal-enter-active,
.zoom-modal-leave-active {
  transition: opacity 0.3s ease;
}

.zoom-modal-enter-from,
.zoom-modal-leave-to {
  opacity: 0;
}

.zoom-modal-enter-active .zoomed-diagram,
.zoom-modal-leave-active .zoomed-diagram {
  transition: transform 0.3s ease;
}

.zoom-modal-enter-from .zoomed-diagram {
  transform: scale(0.8);
}

.zoom-modal-leave-to .zoomed-diagram {
  transform: scale(0.8);
}

@media (max-width: 768px) {
  .diagram-zoom-modal {
    padding: 1rem;
  }
  
  .zoomed-diagram {
    max-height: 80vh;
  }
  
  .zoom-close-button {
    top: -2.5rem;
    width: 36px;
    height: 36px;
  }
}
</style>
