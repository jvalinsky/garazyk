<script setup>
import { ref } from 'vue'

const props = defineProps({
  initialCode: {
    type: String,
    default: 'NSLog(@"Hello, World!");'
  }
})

const code = ref(props.initialCode)
const output = ref('')
const error = ref('')
const isLoading = ref(false)
const executionTime = ref(null)

async function runCode() {
  isLoading.value = true
  output.value = ''
  error.value = ''
  executionTime.value = null

  try {
    const response = await fetch('https://objc-runner.exe.xyz/api/execute', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        code: code.value,
        timeout: 5
      })
    })

    const result = await response.json()

    if (result.success) {
      output.value = result.stdout || '(no output)'
      if (result.stderr) {
        output.value += '\n\nstderr:\n' + result.stderr
      }
      executionTime.value = result.executionTime
    } else {
      error.value = result.stderr || result.stdout || 'Execution failed'
      // If compiler error, show it nicely
      if (result.phase === 'compile') {
         error.value = `Compilation Error:\n${error.value}`
      }
    }
  } catch (e) {
    error.value = `Network Error: ${e.message}`
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <div class="objc-runner">
    <div class="editor-header">
      <span class="lang-tag">Objective-C</span>
      <div class="actions">
        <button 
          @click="runCode" 
          :disabled="isLoading"
          class="run-btn"
        >
          <span v-if="isLoading" class="spinner">↻</span>
          <span v-else>▶ Run</span>
        </button>
      </div>
    </div>
    
    <div class="editor-container">
      <textarea 
        v-model="code" 
        class="code-editor"
        spellcheck="false"
      ></textarea>
    </div>

    <div v-if="output || error || isLoading" class="output-container">
      <div class="output-header">
        <span>Output</span>
        <span v-if="executionTime" class="exec-time">{{ executionTime }}ms</span>
      </div>
      <pre v-if="output" class="output success">{{ output }}</pre>
      <pre v-if="error" class="output error">{{ error }}</pre>
      <div v-if="isLoading && !output && !error" class="output loading">Running on server...</div>
    </div>
  </div>
</template>

<style scoped>
.objc-runner {
  margin: 1.5rem 0;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid var(--vp-c-divider);
  background-color: var(--vp-c-bg-soft);
}

.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 1rem;
  background-color: var(--vp-c-bg-mute);
  border-bottom: 1px solid var(--vp-c-divider);
}

.lang-tag {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--vp-c-text-2);
}

.run-btn {
  background-color: var(--vp-c-brand);
  color: white;
  border: none;
  padding: 0.4rem 1rem;
  border-radius: 4px;
  font-weight: 600;
  cursor: pointer;
  font-size: 0.9rem;
  transition: opacity 0.2s;
}

.run-btn:hover {
  opacity: 0.9;
}

.run-btn:disabled {
  opacity: 0.6;
  cursor: wait;
}

.editor-container {
  position: relative;
}

.code-editor {
  width: 100%;
  min-height: 150px;
  padding: 1rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.9rem;
  background-color: var(--vp-c-bg); 
  color: var(--vp-c-text-1);
  border: none;
  resize: vertical;
  display: block;
}

.code-editor:focus {
  outline: none;
}

.output-container {
  border-top: 1px solid var(--vp-c-divider);
  background-color: #1e1e20; /* Always dark for terminal feel */
  color: #eee;
  padding: 0.5rem 0;
}

.output-header {
  display: flex;
  justify-content: space-between;
  padding: 0 1rem 0.5rem;
  font-size: 0.8rem;
  color: #888;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.output {
  margin: 0;
  padding: 0.5rem 1rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.85rem;
  white-space: pre-wrap;
  overflow-x: auto;
}

.output.error {
  color: #ff6b6b;
  border-left: 3px solid #ff6b6b;
}

.output.success {
  color: #51cf66;
}

.output.loading {
  color: #888;
  font-style: italic;
}

.spinner {
  display: inline-block;
  animation: rotate 1s linear infinite;
}

@keyframes rotate {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
