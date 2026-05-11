import { buildMapsLink, formatCoord, formatVisitedAt } from '../format'
import type { HistoryEntry } from '../types'

type HistoryPanelProps = {
  entries: HistoryEntry[]
  error: string | null
  onRevisit: (entry: HistoryEntry) => void
}

export function HistoryPanel({
  entries,
  error,
  onRevisit,
}: HistoryPanelProps) {
  return (
    <aside className="details-panel history-panel" aria-label="Visit history">
      <header className="details-panel-header history-panel-header">
        <h2>Visit history</h2>
        <span>{entries.length}</span>
      </header>

      <div className="history-content">
        {error ? <p className="history-error">{error}</p> : null}

        {!error && entries.length === 0 ? (
          <p className="muted">No random places yet.</p>
        ) : null}

        {entries.length > 0 ? (
          <ul className="history-list">
            {entries.map((entry) => (
              <li className="history-item" key={entry.id}>
                <div className="history-item-header">
                  <strong>{entry.areaLabel}</strong>
                  <time dateTime={entry.visitedAt}>
                    {formatVisitedAt(entry.visitedAt)}
                  </time>
                </div>

                <div className="history-coordinates">
                  {formatCoord(entry.location.lat)},{' '}
                  {formatCoord(entry.location.lng)}
                </div>

                <div className="history-meta">
                  {entry.date ? `Image date ${entry.date}` : 'Image date unknown'}
                  {' · '}
                  {entry.attempts} {entry.attempts === 1 ? 'try' : 'tries'}
                </div>

                <div className="history-actions">
                  <button
                    type="button"
                    className="compact-action"
                    onClick={() => onRevisit(entry)}
                  >
                    Revisit
                  </button>
                  <a
                    className="compact-action compact-link"
                    href={buildMapsLink(entry)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Open Maps
                  </a>
                </div>
              </li>
            ))}
          </ul>
        ) : null}
      </div>
    </aside>
  )
}
