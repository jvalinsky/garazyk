interface ToolbarProps {
  onRunAll?: () => void;
  onFilterChange?: (query: string) => void;
}

export default function Toolbar({ onRunAll, onFilterChange }: ToolbarProps) {
  return (
    <header class="toolbar">
      <div class="toolbar-section">
        <span class="toolbar-title">Garazyk Scenarios</span>
      </div>
      <div class="toolbar-spacer" />
      <div class="toolbar-section">
        <input
          type="text"
          class="filter-input"
          placeholder="Filter scenarios..."
          onInput={(e) => onFilterChange?.((e.target as HTMLInputElement).value)}
        />
      </div>
      <div class="toolbar-section">
        <button class="btn btn-primary" onClick={onRunAll}>
          Run All ▾
        </button>
      </div>
    </header>
  );
}
