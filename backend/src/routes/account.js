const express = require("express");
const { requireAuth } = require("../utils/authMiddleware");

const router = express.Router();

// Every account route requires a logged-in user; RLS then scopes rows to them.
router.use(requireAuth);

/**
 * Builds a standard per-user CRUD router for a table.
 * GET / (list), POST / (create), PATCH /:id (update), DELETE /:id (remove).
 * Only whitelisted [fields] are ever written.
 */
function crud(table, fields, { order = "created_at", ascending = false } = {}) {
  const r = express.Router();

  const pick = (body) => {
    const out = {};
    for (const f of fields) if (body && body[f] !== undefined) out[f] = body[f];
    return out;
  };

  r.get("/", async (req, res) => {
    try {
      let q = req.supabase.from(table).select("*").eq("user_id", req.user.id);
      // optional ?trip_id= / ?type= filters when the column exists
      if (req.query.trip_id && fields.includes("trip_id")) q = q.eq("trip_id", req.query.trip_id);
      if (req.query.type && fields.includes("type")) q = q.eq("type", req.query.type);
      const { data, error } = await q.order(order, { ascending });
      if (error) throw error;
      res.json(data);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  r.post("/", async (req, res) => {
    try {
      const row = { ...pick(req.body), user_id: req.user.id };
      const { data, error } = await req.supabase.from(table).insert(row).select().single();
      if (error) throw error;
      res.status(201).json(data);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  r.patch("/:id", async (req, res) => {
    try {
      const { data, error } = await req.supabase
        .from(table)
        .update(pick(req.body))
        .eq("id", req.params.id)
        .eq("user_id", req.user.id)
        .select()
        .single();
      if (error) throw error;
      res.json(data);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  r.delete("/:id", async (req, res) => {
    try {
      const { error } = await req.supabase.from(table).delete().eq("id", req.params.id).eq("user_id", req.user.id);
      if (error) throw error;
      res.json({ ok: true });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  return r;
}

// ---- Profile & Settings (single row per user) ----
const PROFILE_FIELDS = ["display_name", "avatar_url", "phone", "home_city", "language", "currency", "theme", "notif_prefs"];

router.get("/profile", async (req, res) => {
  try {
    const { data, error } = await req.supabase.from("user_profiles").select("*").eq("user_id", req.user.id).maybeSingle();
    if (error) throw error;
    res.json(data || { user_id: req.user.id, language: "en", currency: "INR", theme: "dark" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.put("/profile", async (req, res) => {
  try {
    const row = { user_id: req.user.id };
    for (const f of PROFILE_FIELDS) if (req.body[f] !== undefined) row[f] = req.body[f];
    const { data, error } = await req.supabase.from("user_profiles").upsert(row, { onConflict: "user_id" }).select().single();
    if (error) throw error;
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Favorites: Wishlist / Saved Hotels / Saved Destinations (type) ----
router.use("/favorites", crud("favorites", ["type", "name", "ref_id", "lat", "lng", "note", "image_url"]));

// ---- Bookings: flight | hotel | train | bus | car | activity (type) ----
router.use(
  "/bookings",
  crud("bookings", ["type", "title", "provider", "reference", "start_time", "end_time", "from_loc", "to_loc", "seat", "status", "price", "currency", "details"])
);

// ---- Budget: expenses + budgets + wallet balance ----
router.use("/expenses", crud("expenses", ["trip_id", "category", "amount", "currency", "note", "spent_at"], { order: "spent_at" }));
router.use("/budgets", crud("budgets", ["trip_id", "total", "currency", "breakdown"]));

// ---- Travel Tools ----
router.use("/documents", crud("documents", ["type", "title", "file_url", "expires_at", "note"]));
router.use("/emergency", crud("emergency_contacts", ["name", "relation", "phone", "category", "is_local_service", "blood_group", "medical_notes"]));
router.use("/packing", crud("packing_items", ["trip_id", "category", "name", "qty", "packed"]));

// ---- Notifications (PATCH read:true to mark read) ----
router.use("/notifications", crud("notifications", ["type", "title", "body", "read", "scheduled_at"]));

module.exports = router;
