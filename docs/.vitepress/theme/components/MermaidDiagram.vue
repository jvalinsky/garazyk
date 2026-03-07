<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useData } from 'vitepress'

const props = defineProps<{
  graph: string
}>()

const containerEl = ref<HTMLElement | null>(null)
const errorMessage = ref('')
const { isDark } = useData()
const instanceId = `vp-mermaid-${Math.random().toString(36).slice(2, 10)}`

let renderSequence = 0

const decodedGraph = computed(() => decodeURIComponent(props.graph))

async function renderDiagram() {
  if (!containerEl.value || typeof window === 'undefined') {
    return
  }

  const mermaidModule = await import('mermaid')
  const mermaid = mermaidModule.default
  const currentRender = ++renderSequence

  errorMessage.value = ''
  containerEl.value.innerHTML = ''

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    suppressErrorRendering: true,
    theme: isDark.value ? 'dark' : 'neutral',
    fontFamily: 'var(--vp-font-family-base)',
    flowchart: {
      htmlLabels: true,
      useMaxWidth: true,
    },
    sequence: {
      useMaxWidth: true,
    },
  })

  try {
    const { svg, bindFunctions } = await mermaid.render(
      `${instanceId}-${currentRender}`,
      decodedGraph.value
    )

    if (!containerEl.value || currentRender !== renderSequence) {
      return
    }

    containerEl.value.innerHTML = svg
    bindFunctions?.(containerEl.value)
  } catch (error) {
    if (!containerEl.value || currentRender !== renderSequence) {
      return
    }

    const message =
      error instanceof Error ? error.message : 'Unknown Mermaid render error'

    errorMessage.value = message
    containerEl.value.textContent = decodedGraph.value
  }
}

onMounted(() => {
  void renderDiagram()
})

watch(isDark, () => {
  void renderDiagram()
})
</script>

<template>
  <figure class="mermaid-diagram">
    <div
      ref="containerEl"
      class="mermaid-diagram__canvas"
      :class="{ 'mermaid-diagram__canvas--error': errorMessage }"
      role="img"
      aria-label="Rendered Mermaid diagram"
    />
    <figcaption v-if="errorMessage" class="mermaid-diagram__error">
      Mermaid render failed: {{ errorMessage }}
    </figcaption>
  </figure>
</template>
