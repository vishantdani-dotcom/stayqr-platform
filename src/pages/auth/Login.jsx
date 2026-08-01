import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import logo from '../../assets/stayqr-logo.png'
import './Login.css'

const MODE_CONTENT = {
  login: {
    subtitle: 'Secure Staff Access',
    title: 'Sign in to StayQR',
    helper: 'Use the verified email linked to your hotel or platform identity.',
  },
  signup: {
    subtitle: 'Hotel Owner Registration',
    title: 'Create your StayQR account',
    helper: 'Register the hotel owner account first. The secure setup wizard will create the hotel after authentication.',
  },
  forgot: {
    subtitle: 'Account Recovery',
    title: 'Reset your password',
    helper: 'We will email a secure recovery link to your verified account.',
  },
}

export default function Login() {
  const [mode, setMode] = useState('login')
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [errorMessage, setErrorMessage] = useState('')

  const content = MODE_CONTENT[mode]

  function changeMode(nextMode) {
    setMode(nextMode)
    setMessage('')
    setErrorMessage('')
    setPassword('')
    setConfirmPassword('')
  }

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

  async function handleSignup(event) {
    event.preventDefault()
    setMessage('')
    setErrorMessage('')

    const normalizedName = fullName.trim()
    const normalizedEmail = email.trim().toLowerCase()

    if (normalizedName.length < 2) {
      setErrorMessage('Enter the hotel owner’s full name.')
      return
    }

    if (password.length < 8) {
      setErrorMessage('Use a password with at least 8 characters.')
      return
    }

    if (password !== confirmPassword) {
      setErrorMessage('Password and confirmation do not match.')
      return
    }

    setLoading(true)

    const { data, error } = await supabase.auth.signUp({
      email: normalizedEmail,
      password,
      options: {
        data: {
          full_name: normalizedName,
          account_type: 'hotel_owner',
        },
        emailRedirectTo: `${window.location.origin}/`,
      },
    })

    setLoading(false)

    if (error) {
      setErrorMessage(error.message)
      return
    }

    if (data.session) {
      window.location.replace('/')
      return
    }

    setMessage(
      'Account created. Check your email and verify the address, then sign in to continue with secure hotel setup.'
    )
    setPassword('')
    setConfirmPassword('')
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

  const submitHandler =
    mode === 'login'
      ? handleLogin
      : mode === 'signup'
        ? handleSignup
        : handleForgotPassword

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <img src={logo} alt="StayQR" className="login-logo" />
          <p className="login-subtitle">{content.subtitle}</p>
          <h1>{content.title}</h1>
          <p className="login-helper">{content.helper}</p>
        </div>

        {mode !== 'forgot' && (
          <div className="login-mode-switch" aria-label="Authentication mode">
            <button
              type="button"
              className={mode === 'login' ? 'active' : ''}
              onClick={() => changeMode('login')}
              disabled={loading}
            >
              Sign in
            </button>
            <button
              type="button"
              className={mode === 'signup' ? 'active' : ''}
              onClick={() => changeMode('signup')}
              disabled={loading}
            >
              Create owner account
            </button>
          </div>
        )}

        {message && <div className="login-message success">{message}</div>}
        {errorMessage && <div className="login-message error">{errorMessage}</div>}

        <form onSubmit={submitHandler}>
          {mode === 'signup' && (
            <label>
              Hotel owner name
              <input
                type="text"
                autoComplete="name"
                placeholder="Owner’s full name"
                value={fullName}
                onChange={(event) => setFullName(event.target.value)}
                required
              />
            </label>
          )}

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

          {mode !== 'forgot' && (
            <label>
              Password
              <input
                type="password"
                autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
                placeholder={mode === 'signup' ? 'Minimum 8 characters' : 'Your password'}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
                minLength={mode === 'signup' ? 8 : undefined}
              />
            </label>
          )}

          {mode === 'signup' && (
            <label>
              Confirm password
              <input
                type="password"
                autoComplete="new-password"
                placeholder="Repeat your password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                required
                minLength={8}
              />
            </label>
          )}

          <button type="submit" disabled={loading}>
            {loading
              ? mode === 'login'
                ? 'Signing in…'
                : mode === 'signup'
                  ? 'Creating account…'
                  : 'Sending recovery link…'
              : mode === 'login'
                ? 'Sign in securely'
                : mode === 'signup'
                  ? 'Create owner account'
                  : 'Send recovery link'}
          </button>
        </form>

        {mode === 'login' && (
          <button
            type="button"
            className="login-link-button"
            onClick={() => changeMode('forgot')}
            disabled={loading}
          >
            Forgot password?
          </button>
        )}

        {mode === 'forgot' && (
          <button
            type="button"
            className="login-link-button"
            onClick={() => changeMode('login')}
            disabled={loading}
          >
            Back to sign in
          </button>
        )}

        <p className="login-security-note">
          Hotel owners may create a new account here. Staff members must use
          the invitation sent by their owner, manager or StayQR platform
          administrator.
        </p>
      </div>
    </div>
  )
}
