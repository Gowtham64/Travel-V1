const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL || "https://dtemayjpttktntooxraa.supabase.co";
const supabaseKey = process.env.SUPABASE_ANON_KEY || "sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh";

/**
 * Express middleware to verify Supabase JWT token from Authorization header.
 */
async function requireAuth(req, res, next) {
  if (!supabaseUrl || !supabaseKey) {
    return res.status(503).json({ error: "Supabase not configured" });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = authHeader.split(' ')[1];

  // Create a user-scoped client that includes the user's JWT token in headers
  const userSupabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${token}`
      }
    }
  });

  const { data: { user }, error } = await userSupabase.auth.getUser(token);

  if (error || !user) {
    return res.status(401).json({ error: "Invalid token" });
  }

  req.user = user;
  req.supabase = userSupabase;
  next();
}

module.exports = { requireAuth };
