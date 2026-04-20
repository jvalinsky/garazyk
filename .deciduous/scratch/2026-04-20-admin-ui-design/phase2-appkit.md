# Phase 2: AppKit Authenticity

## Decision Node: 10

## Goals

### 1. NSVisualEffectView Materials
Add macOS vibrancy effects to sidebar and toolbar

### 2. NSToolbar Segmented Control
True macOS toolbar segmented control styling

### 3. Window Chrome
Title bar and window control styling

### 4. Status Bar
AppKit-style status bar (like Finder)

## Implementation

### NSVisualEffectView
Using CSS backdrop-filter as approximation:
```css
.sidebar {
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
}
```

### True Toolbar
Replace generic segmented control with NSSegmentedControl styling

### Window Title Bar
Add traffic light buttons (close, minimize, zoom) styling

## Files to Modify
- layout.css - Add vibrancy effects
- components.css - Add segmented control
- tokens.css - Optional: add material colors