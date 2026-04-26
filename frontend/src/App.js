import React, { useState } from 'react';
import Login from './components/Login';
import Dashboard from './pages/Dashboard';

function isAuthenticated() {
  return Boolean(localStorage.getItem('idToken'));
}

export default function App() {
  const [authed, setAuthed] = useState(isAuthenticated);

  return authed ? (
    <Dashboard onLogout={() => setAuthed(false)} />
  ) : (
    <Login onLogin={() => setAuthed(true)} />
  );
}
