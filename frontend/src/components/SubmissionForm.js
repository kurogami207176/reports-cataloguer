import React, { useState } from 'react';
import { createSubmission } from '../api/submissions';
import './SubmissionForm.css';

export default function SubmissionForm({ onSubmitted }) {
  const [text, setText] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!text.trim()) return;
    setError('');
    setSuccess('');
    setLoading(true);
    try {
      await createSubmission(text.trim());
      setSuccess('Submission saved successfully!');
      setText('');
      onSubmitted && onSubmitted();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to save submission.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="submission-form card">
      <h2 className="sf-title">New Submission</h2>

      {error && <div className="alert alert-error" style={{ marginBottom: '1rem' }}>{error}</div>}
      {success && <div className="alert alert-success" style={{ marginBottom: '1rem' }}>{success}</div>}

      <form onSubmit={handleSubmit}>
        <div className="form-group">
          <label htmlFor="submission-text">Your report</label>
          <textarea
            id="submission-text"
            rows={5}
            required
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="Write your report here…"
          />
        </div>
        <button
          type="submit"
          className="btn btn-primary sf-btn"
          disabled={loading || !text.trim()}
        >
          {loading ? 'Saving…' : 'Submit'}
        </button>
      </form>
    </div>
  );
}
