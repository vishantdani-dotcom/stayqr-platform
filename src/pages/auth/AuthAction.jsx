import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import logo from '../../assets/stayqr-logo.png'
import './Login.css'

export default function AuthAction({ mode, session }) {
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')

  const isInvite = mode === 'invite'

  async function handleSubmit(event) {
    event.preventDefault()
    setErrorMessage('')

    if (!session) {
      setErrorMessage('This secure link is invalid or has expired.')
      return
    }

    if (password.length < 8) {
      setErrorMessage('Use a password with at least 8 characters.')
      return
    }

    if (password !== confirmPassword) {
      setErrorMessage('The passwords do not match.')
      return
    }

    setLoading(true)

    const { error: passwordError } = await supabase.auth.updateUser({
      password,
    })

    if (passwordError) {
      setLoading(false)
      setErrorMessage(passwordError.message)
      return
    }

    const { error: activationError } = await supabase.rpc(
      'activate_my_staff_invitation'
    )

    if (activationError && !['42883', 'PGRST202'].includes(activationError.code)) {
      setLoading(false)
      setErrorMessage(activationError.message)
      return
    }

    window.location.replace('/')
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <img src={logo} alt="StayQR" className="login-logo" />
          <p className="login-subtitle">
            {isInvite ? 'Complete Staff Invitation' : 'Password Recovery'}
          </p>
          <h1>{isInvite ? 'Create your StayQR password' : 'Choose a new password'}</h1>
          <p className="login-helper">
            {session
              ? 'Set a strong password to finish securing your account.'
              : 'Open the latest secure link from your email and try again.'}
          </p>
        </div>

        {errorMessage && <div className="login-message error">{errorMessage}</div>}

        {session ? (
          <form onSubmit={handleSubmit}>
            <label>
              New password
              <input
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="At least 8 characters"
                required
              />
            </label>

            <label>
              Confirm new password
              <input
                type="password"
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                placeholder="Repeat your password"
                required
              />
            </label>

            <button type="submit" disabled={loading}>
              {loading
                ? 'Securing account…'
                : isInvite
                  ? 'Complete invitation'
                  : 'Update password'}
            </button>
          </form>
        ) : (
          <button type="button" onClick={() => window.location.replace('/')}>
            Return to sign in
          </button>
        )}
      </div>
    </div>
  )
}
