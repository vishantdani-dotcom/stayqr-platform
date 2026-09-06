import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import logo from '../../assets/stayqr-logo.png'
import heroImage from '../../assets/hero.png'
import './Login.css'

const MODE_CONTENT = {
  login: {
    eyebrow: 'Secure staff access',
    title: 'Welcome back',
    helper: 'Sign in with the verified email linked to your StayQR hotel or platform account.',
    submit: 'Sign in securely',
  },
  signup: {
    eyebrow: 'Hotel owner registration',
    title: 'Create your StayQR account',
    helper: 'Create the hotel owner account first. Secure property setup continues after authentication.',
    submit: 'Create owner account',
  },
  forgot: {
    eyebrow: 'Account recovery',
    title: 'Reset your password',
    helper: 'Enter your account email and we will send a secure recovery link.',
    submit: 'Send recovery link',
  },
}

export default function Login({ initialMode = 'login' }) {
  const [mode, setMode] = useState(initialMode)
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [errorMessage, setErrorMessage] = useState('')

  const content = MODE_CONTENT[mode]

  function getPostAuthTarget() {
    const params = new URLSearchParams(window.location.search)
    const requestedNext = params.get('next')
    if (requestedNext?.startsWith('/') && !requestedNext.startsWith('//')) {
      return requestedNext
    }

    if (['/checkout/success', '/checkout/recover'].includes(window.location.pathname)) {
      return `${window.location.pathname}${window.location.search}`
    }

    const acquisitionRequested =
      window.location.pathname === '/signup' ||
      window.location.pathname === '/checkout' ||
      params.has('plan') ||
      params.has('mode')

    if (!acquisitionRequested) return '/'

    const checkoutParams = new URLSearchParams()
    for (const key of ['plan', 'billing', 'mode']) {
      const value = params.get(key)
      if (value) checkoutParams.set(key, value)
    }
    const query = checkoutParams.toString()
    return `/checkout${query ? `?${query}` : ''}`
  }

  function changeMode(nextMode) {
    setMode(nextMode)
    setMessage('')
    setErrorMessage('')
    setPassword('')
    setConfirmPassword('')
    setShowPassword(false)
    setShowConfirmPassword(false)
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

    window.location.replace(getPostAuthTarget())
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
        emailRedirectTo: `${window.location.origin}${getPostAuthTarget()}`,
      },
    })

    setLoading(false)

    if (error) {
      setErrorMessage(error.message)
      return
    }

    if (data.session) {
      window.location.replace(getPostAuthTarget())
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

    const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail, {
      redirectTo: `${window.location.origin}/auth/reset-password`,
    })

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
    <main className="sq-login-page">
      <section className="sq-login-shell" aria-label="StayQR account access">
        <aside className="sq-login-visual">
          <div className="sq-login-visual-media" aria-hidden="true">
            <img src={heroImage} alt="" />
            <div className="sq-login-visual-shade" />
            <div className="sq-login-orbit sq-login-orbit-a" />
            <div className="sq-login-orbit sq-login-orbit-b" />
          </div>

          <div className="sq-login-visual-content">
            <div className="sq-login-wordmark">
              <img src={logo} alt="StayQR" />
              <div>
                <strong>StayQR</strong>
                <span>Simplifying Checkinn</span>
              </div>
            </div>

            <div className="sq-login-visual-copy">
              <span className="sq-login-kicker">HOTEL OPERATIONS · GUEST EXPERIENCE</span>
              <h2>One workspace for the stay, from arrival to checkout.</h2>
              <p>
                Front desk operations, guest identity, room QR guides, service workflows and stay billing — connected in one secure hotel workspace.
              </p>
            </div>

            <div className="sq-login-capabilities" aria-label="StayQR capabilities">
              <article>
                <span className="sq-login-capability-icon"><QrIcon /></span>
                <div><strong>QR-first guest experience</strong><small>Personalised room access during the active stay.</small></div>
              </article>
              <article>
                <span className="sq-login-capability-icon"><ShieldIcon /></span>
                <div><strong>Secure hotel access</strong><small>Role-aware staff and platform authentication.</small></div>
              </article>
              <article>
                <span className="sq-login-capability-icon"><BoltIcon /></span>
                <div><strong>Operational clarity</strong><small>Check-in, service, billing and room status in one place.</small></div>
              </article>
            </div>
          </div>
        </aside>

        <section className="sq-login-panel">
          <div className="sq-login-mobile-brand">
            <img src={logo} alt="StayQR" />
            <div><strong>StayQR</strong><span>Simplifying Checkinn</span></div>
          </div>

          <div className="sq-login-form-wrap">
            <div className="sq-login-heading">
              <span>{content.eyebrow}</span>
              <h1>{content.title}</h1>
              <p>{content.helper}</p>
            </div>

            {mode !== 'forgot' && (
              <div className="sq-login-mode-switch" aria-label="Authentication mode">
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

            {message && <div className="sq-login-message success">{message}</div>}
            {errorMessage && <div className="sq-login-message error">{errorMessage}</div>}

            <form className="sq-login-form" onSubmit={submitHandler}>
              {mode === 'signup' && (
                <label>
                  <span>Hotel owner name</span>
                  <div className="sq-login-field">
                    <UserIcon />
                    <input
                      type="text"
                      autoComplete="name"
                      placeholder="Owner’s full name"
                      value={fullName}
                      onChange={(event) => setFullName(event.target.value)}
                      required
                    />
                  </div>
                </label>
              )}

              <label>
                <span>Email address</span>
                <div className="sq-login-field">
                  <MailIcon />
                  <input
                    type="email"
                    autoComplete="email"
                    inputMode="email"
                    placeholder="name@example.com"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    required
                  />
                </div>
              </label>

              {mode !== 'forgot' && (
                <label>
                  <span>Password</span>
                  <div className="sq-login-field">
                    <LockIcon />
                    <input
                      type={showPassword ? 'text' : 'password'}
                      autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
                      placeholder={mode === 'signup' ? 'Minimum 8 characters' : 'Your password'}
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                      required
                      minLength={mode === 'signup' ? 8 : undefined}
                    />
                    <button
                      type="button"
                      className="sq-login-reveal"
                      onClick={() => setShowPassword((value) => !value)}
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                    >
                      {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                    </button>
                  </div>
                </label>
              )}

              {mode === 'signup' && (
                <label>
                  <span>Confirm password</span>
                  <div className="sq-login-field">
                    <LockIcon />
                    <input
                      type={showConfirmPassword ? 'text' : 'password'}
                      autoComplete="new-password"
                      placeholder="Repeat your password"
                      value={confirmPassword}
                      onChange={(event) => setConfirmPassword(event.target.value)}
                      required
                      minLength={8}
                    />
                    <button
                      type="button"
                      className="sq-login-reveal"
                      onClick={() => setShowConfirmPassword((value) => !value)}
                      aria-label={showConfirmPassword ? 'Hide password' : 'Show password'}
                    >
                      {showConfirmPassword ? <EyeOffIcon /> : <EyeIcon />}
                    </button>
                  </div>
                </label>
              )}

              <button className="sq-login-submit" type="submit" disabled={loading}>
                <span>
                  {loading
                    ? mode === 'login'
                      ? 'Signing in…'
                      : mode === 'signup'
                        ? 'Creating account…'
                        : 'Sending recovery link…'
                    : content.submit}
                </span>
                {!loading && <ArrowIcon />}
                {loading && <span className="sq-login-spinner" aria-hidden="true" />}
              </button>
            </form>

            {mode === 'login' && (
              <button
                type="button"
                className="sq-login-link"
                onClick={() => changeMode('forgot')}
                disabled={loading}
              >
                Forgot password?
              </button>
            )}

            {mode === 'forgot' && (
              <button
                type="button"
                className="sq-login-link"
                onClick={() => changeMode('login')}
                disabled={loading}
              >
                ← Back to sign in
              </button>
            )}

            <div className="sq-login-security-note">
              <ShieldIcon />
              <p>
                Hotel owners can create an account here. Staff members should use the secure invitation sent by their owner, manager or StayQR platform administrator.
              </p>
            </div>
          </div>

          <footer className="sq-login-footer">
            <span>© {new Date().getFullYear()} StayQR</span>
            <div>
              <a href="/privacy" target="_blank" rel="noreferrer">Privacy</a>
              <a href="/terms" target="_blank" rel="noreferrer">Terms</a>
              <a href="/legal" target="_blank" rel="noreferrer">Legal</a>
            </div>
          </footer>
        </section>
      </section>
    </main>
  )
}

function SvgIcon({ children, viewBox = '0 0 24 24' }) {
  return <svg viewBox={viewBox} fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{children}</svg>
}
function MailIcon() { return <SvgIcon><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></SvgIcon> }
function LockIcon() { return <SvgIcon><rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></SvgIcon> }
function UserIcon() { return <SvgIcon><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></SvgIcon> }
function EyeIcon() { return <SvgIcon><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/></SvgIcon> }
function EyeOffIcon() { return <SvgIcon><path d="m3 3 18 18"/><path d="M10.6 6.2A11 11 0 0 1 12 6c6.5 0 10 6 10 6a16 16 0 0 1-2.2 2.8M6.2 6.2C3.5 8 2 12 2 12s3.5 6 10 6c1.2 0 2.3-.2 3.2-.5"/><path d="M10.2 10.2A2.6 2.6 0 0 0 13.8 13.8"/></SvgIcon> }
function ArrowIcon() { return <SvgIcon><path d="M5 12h14"/><path d="m14 7 5 5-5 5"/></SvgIcon> }
function ShieldIcon() { return <SvgIcon><path d="M12 22s8-3.5 8-10V5l-8-3-8 3v7c0 6.5 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/></SvgIcon> }
function QrIcon() { return <SvgIcon><rect x="3" y="3" width="6" height="6"/><rect x="15" y="3" width="6" height="6"/><rect x="3" y="15" width="6" height="6"/><path d="M15 15h2v2h-2zM19 15h2v6h-6v-2"/></SvgIcon> }
function BoltIcon() { return <SvgIcon><path d="M13 2 4.5 13H11l-1 9L19.5 10H13l0-8Z"/></SvgIcon> }
