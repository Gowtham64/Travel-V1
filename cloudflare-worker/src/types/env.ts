import type { User, SupabaseClient } from '@supabase/supabase-js';

export interface Env {
  // Config & Metadata
  APP_VERSION?: string;
  ALLOWED_ORIGINS?: string;
  ENVIRONMENT?: string;

  // Supabase Bindings & Secrets
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;

  // AI Service Keys
  GEMINI_API_KEY?: string;
  GOOGLE_API_KEY?: string;
  GROQ_API_KEY?: string;
  OPENROUTER_API_KEY?: string;

  // Mapping & Routing API Keys
  MAPBOX_TOKEN?: string;
  ORS_API_KEY?: string;
  TOLLGURU_API_KEY?: string;

  // Admin Tokens
  PRICE_ADMIN_TOKEN?: string;
}

export interface AppVariables {
  requestId: string;
  user?: User;
  supabase?: SupabaseClient;
}

export type Variables = AppVariables;

