const { supabase } = require('../services/dbService');

/**
 * Express middleware to verify Supabase JWT token from Authorization header.
 */
async function requireAuth(req, res, next) {
  if (!supabase) {
    // If Supabase isn't configured, bypass auth (or fail, depending on env)
    return res.status(503).json({ error: "Supabase not configured" });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = authHeader.split(' ')[1];

  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    return res.status(401).json({ error: "Invalid token" });
  }

  req.user = user;
  next();
}

module.exports = { requireAuth };
