import React, { useState, useCallback } from 'react';
import SubmissionForm from '../components/SubmissionForm';
import SubmissionList from '../components/SubmissionList';
import './Dashboard.css';

export default function Dashboard({ onLogout }) {
  const [refreshToken, setRefreshToken] = useState(0);

  const handleSubmitted = useCallback(() => {
    setRefreshToken((t) => t + 1);
  }, []);

  const handleLogout = () => {
    localStorage.clear();
    onLogout();
  };

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <span className="dashboard-brand">Reports Cataloguer</span>
        <button className="btn btn-ghost btn-sm" onClick={handleLogout}>
          Sign out
        </button>
      </header>

      <main className="dashboard-content">
        <SubmissionForm onSubmitted={handleSubmitted} />
        <SubmissionList refreshToken={refreshToken} />
      </main>
    </div>
  );
}
