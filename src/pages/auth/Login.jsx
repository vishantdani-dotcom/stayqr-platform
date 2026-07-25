import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import logo from '../../assets/stayqr-logo.png'
import './Login.css'

export default function Login() {
  const [mode, setMode] = useState('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [errorMessage, setErrorMessage] = useState('')

  async function handleLogin(event) {
    event.preventDefault()
    setLoading(true)
    setMessage('')
    setErrorMessage('')

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    })

    setLoading(false)

    if (error) {
      setErrorMessage(error.message)
      return
    }

    window.location.replace('/')
  }

  async function handleForgotPassword(event) {
    event.preventDefault()
    setLoading(true)
    setMessage('')
    setErrorMessage('')

    const normalizedEmail = email.trim().toLowerCase()

    if (!normalizedEmail) {
      setLoading(false)
      setErrorMessage('Enter your StayQR account email.')
      return
    }

    const { error } = await supabase.auth.resetPasswordForEmail(
      normalizedEmail,
      {
        redirectTo: `${window.location.origin}/auth/reset-password`,
      }
    )

    setLoading(false)

    if (error) {
      setErrorMessage(error.message)
      return
    }

    setMessage(
      'Password reset instructions have been sent when this email belongs to an active StayQR account.'
    )
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <img src={logo} alt="StayQR" className="login-logo" />
          <p className="login-subtitle">Secure Staff Access</p>
          <h1>{mode === 'login' ? 'Sign in to StayQR' : 'Reset your password'}</h1>
          <p className="login-helper">
            {mode === 'login'
              ? 'Use the verified email linked to your hotel or platform identity.'
              : 'We will email a secure recovery link to your verified account.'}
          </p>
        </div>

        {message && <div className="login-message success">{message}</div>}
        {errorMessage && <div className="login-message error">{errorMessage}</div>}

        <form onSubmit={mode === 'login' ? handleLogin : handleForgotPassword}>
          <label>
            Email address
            <input
              type="email"
              autoComplete="email"
              placeholder="name@example.com"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>

          {mode === 'login' && (
            <label>
              Password
              <input
                type="password"
                autoComplete="current-password"
                placeholder="Your password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
              />
            </label>
          )}

          <button type="submit" disabled={loading}>
            {loading
              ? mode === 'login'
                ? 'Signing in…'
                : 'Sending recovery link…'
              : mode === 'login'
                ? 'Sign in securely'
                : 'Send recovery link'}
          </button>
        </form>

        <button
          type="button"
          className="login-link-button"
          onClick={() => {
            setMode((current) => (current === 'login' ? 'forgot' : 'login'))
            setMessage('')
            setErrorMessage('')
          }}
        >
          {mode === 'login' ? 'Forgot password?' : 'Back to sign in'}
        </button>

        <p className="login-security-note">
          New staff must accept the invitation sent by an owner, manager or
          StayQR platform administrator.
        </p>
      </div>
    </div>
  )
}
