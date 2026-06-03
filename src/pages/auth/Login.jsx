// src/pages/auth/Login.jsx

import { useState } from "react";
import { supabase } from "../../lib/supabase";
import logo from "../../assets/stayqr-logo.png";
import "./Login.css";

export default function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e) => {
    e.preventDefault();

    setLoading(true);

    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    setLoading(false);

    if (error) {
      alert(error.message);
      return;
    }

    window.location.reload();
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <img src={logo} alt="StayQR" className="login-logo" />
          <p className="login-subtitle">Hotel Admin Access</p>
        </div>

        <form onSubmit={handleLogin}>
          <input
            type="email"
            placeholder="Hotel admin email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />

          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />

          <button type="submit" disabled={loading}>
            {loading ? "Signing In..." : "Login to Dashboard"}
          </button>
        </form>
      </div>
    </div>
  );
}