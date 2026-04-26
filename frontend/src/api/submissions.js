import api from './client';

export const login = (email, password) =>
  api.post('/api/auth/login', { email, password });

export const createSubmission = (text) =>
  api.post('/api/submissions', { text });

export const listSubmissions = () =>
  api.get('/api/submissions');
