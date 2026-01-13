import DefaultTheme from 'vitepress/theme'
import ObjcRunner from './components/ObjcRunner.vue'
import './custom.css'

export default {
    ...DefaultTheme,
    enhanceApp({ app }) {
        app.component('ObjcRunner', ObjcRunner)
    }
}
