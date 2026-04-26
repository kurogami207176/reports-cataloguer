import React, { useEffect, useState, useCallback } from 'react';
import { listSubmissions } from '../api/submissions';
import './SubmissionList.css';

// Month names indexed 1-12; index 0 is an empty placeholder so that
// MONTH_NAMES[monthNumber] works directly without subtracting 1.
const MONTH_NAMES = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export default function SubmissionList({ refreshToken }) {
  const [grouped, setGrouped] = useState(null);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const fetchSubmissions = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const { data } = await listSubmissions();
      setGrouped(data.submissions);
      setTotal(data.total);
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to load submissions.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchSubmissions(); }, [fetchSubmissions, refreshToken]);

  if (loading) return <div className="sl-loading">Loading submissions…</div>;
  if (error)   return <div className="alert alert-error">{error}</div>;

  const years = grouped ? Object.keys(grouped).sort((a, b) => b - a) : [];

  return (
    <div className="submission-list card">
      <div className="sl-header">
        <h2 className="sl-title">Your Submissions</h2>
        <span className="sl-count">{total} {total === 1 ? 'entry' : 'entries'}</span>
      </div>

      {years.length === 0 && (
        <p className="sl-empty">No submissions yet. Use the form above to add your first one!</p>
      )}

      {years.map((year) => {
        const months = Object.keys(grouped[year]).sort((a, b) => b - a);
        return (
          <div key={year} className="sl-year">
            <h3 className="sl-year-label">{year}</h3>
            {months.map((month) => {
              const days = Object.keys(grouped[year][month]).sort((a, b) => b - a);
              return (
                <div key={month} className="sl-month">
                  <h4 className="sl-month-label">
                    {MONTH_NAMES[parseInt(month, 10)] || month}
                  </h4>
                  {days.map((day) => {
                    const items = grouped[year][month][day];
                    return (
                      <div key={day} className="sl-day">
                        <span className="sl-day-label">
                          {MONTH_NAMES[parseInt(month, 10)]} {parseInt(day, 10)}, {year}
                        </span>
                        {items.map((item) => (
                          <div key={item.id} className="sl-item">
                            <p className="sl-item-text">{item.text}</p>
                            <span className="sl-item-time">
                              {new Date(item.createdAt).toLocaleTimeString([], {
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          </div>
                        ))}
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </div>
        );
      })}
    </div>
  );
}
