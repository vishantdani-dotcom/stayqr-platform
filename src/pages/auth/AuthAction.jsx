import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import logo from '../../assets/stayqr-logo.png'
import './Login.css'

export default function AuthAction({ mode, session }) {
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
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
    <main className="sq-auth-action-page" data-password-reveal="enabled">
      <section className="sq-auth-action-card">
        <div className="sq-auth-action-brand">
          <img src={logo} alt="StayQR" className="sq-auth-action-logo" />
          <p className="sq-auth-action-subtitle">
            {isInvite ? 'Complete Staff Invitation' : 'Password Recovery'}
          </p>
          <h1>{isInvite ? 'Create your StayQR password' : 'Choose a new password'}</h1>
          <p className="sq-auth-action-helper">
            {session
              ? 'Set a strong password to finish securing your account.'
              : 'Open the latest secure link from your email and try again.'}
          </p>
        </div>

        {errorMessage && <div className="sq-auth-action-message error">{errorMessage}</div>}

        {session ? (
          <form onSubmit={handleSubmit}>
            <label>
              <span>New password</span>
              <div className="sq-auth-password-field">
                <input
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="new-password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="At least 8 characters"
                  required
                />
                <button
                  type="button"
                  className="sq-auth-password-toggle"
                  onClick={() => setShowPassword((value) => !value)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
            </label>

            <label>
              <span>Confirm new password</span>
              <div className="sq-auth-password-field">
                <input
                  type={showConfirmPassword ? 'text' : 'password'}
                  autoComplete="new-password"
                  value={confirmPassword}
                  onChange={(event) => setConfirmPassword(event.target.value)}
                  placeholder="Repeat your password"
                  required
                />
                <button
                  type="button"
                  className="sq-auth-password-toggle"
                  onClick={() => setShowConfirmPassword((value) => !value)}
                  aria-label={showConfirmPassword ? 'Hide password' : 'Show password'}
                >
                  {showConfirmPassword ? 'Hide' : 'Show'}
                </button>
              </div>
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
      </section>
    </main>
  )
}
