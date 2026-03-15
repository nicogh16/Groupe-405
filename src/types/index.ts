export interface App {
  id: string
  name: string
  slug: "myfidelity" | "studioconnect"
  description: string | null
  icon_url: string | null
  logo_url: string | null
  color: string
  github_dashboard_repo: string | null
  github_mobile_repo: string | null
  vercel_dashboard_url: string | null
  tech_stack: string[]
  created_at: string
}

export interface Client {
  id: string
  app_id: string
  name: string
  slug: string
  supabase_project_ref: string | null
  supabase_url: string | null
  // Note: la clé service_role est stockée chiffrée en DB, jamais exposée côté code
  supabase_plan: "free" | "pro" | "team" | "enterprise"
  monthly_revenue: number
  annual_revenue: number // computed: monthly_revenue * 12
  vercel_project_url: string | null
  github_repo_url: string | null
  status: "active" | "paused" | "inactive"
  notes: string | null
  created_at: string
  updated_at: string
}

export interface ClientWithApp extends Client {
  app: App
}

export interface UsageSnapshot {
  id: string
  client_id: string
  registered_users_count: number
  database_size_bytes: number
  storage_size_bytes: number
  api_requests_count: number
  monthly_active_users: number
  edge_function_invocations: number
  realtime_messages: number
  estimated_monthly_cost: number
  snapshot_date: string
  created_at: string
}

export interface ClientMetrics {
  registeredUsersCount: number
  databaseSizeBytes: number
  storageSizeBytes: number
  apiRequestsCount: number
  monthlyActiveUsers: number
  edgeFunctionInvocations: number
  realtimeMessages: number
  estimatedMonthlyCost: number
  // Pourcentages d'utilisation
  storageUsagePercent: number
  mauUsagePercent: number
  databaseUsagePercent: number
  edgeFunctionUsagePercent: number
  realtimeUsagePercent: number
}

export interface DashboardStats {
  totalClients: number
  activeClients: number
  totalAnnualRevenue: number
  totalAnnualCost: number
  totalUsers: number
  netMargin: number
}

export interface Profile {
  id: string
  full_name: string
  role: "admin" | "viewer"
  avatar_url: string | null
  created_at: string
}

export interface AuditLogEntry {
  id: string
  user_id: string | null
  action: string
  target_client_id: string | null
  details: Record<string, unknown> | null
  ip_address: string | null
  created_at: string
}

export interface Expense {
  id: string
  client_id: string
  description: string
  amount: number
  category: string | null
  expense_date: string
  is_recurring: boolean
  recurring_frequency: "monthly" | "yearly" | null
  notes: string | null
  created_at: string
  updated_at: string
}

// =====================================================
// Provisioning System
// =====================================================

export interface StorageBucketConfig {
  name: string
  public: boolean
  file_size_limit: number | null
  allowed_mime_types: string[] | null
}

export interface EnvVarTemplate {
  key: string
  description: string
  auto?: boolean
  secret?: boolean
}

export interface SchemaTableInfo {
  name: string
  columns: number
  description: string
}

export interface SchemaFunctionInfo {
  name: string
  description: string
}

export interface SchemaViewInfo {
  name: string
  description: string
}

export interface SchemaCustomType {
  name: string
  type: string
  values: string[]
}

export interface SchemaSnapshot {
  schemas: string[]
  tables: Record<string, SchemaTableInfo[]>
  functions: Record<string, SchemaFunctionInfo[]>
  views: Record<string, SchemaViewInfo[]>
  custom_types: SchemaCustomType[]
}

export interface ProjectTemplate {
  id: string
  app_id: string
  name: string
  description: string | null
  github_template_owner: string
  github_template_repo: string
  github_migrations_path: string
  default_supabase_plan: "free" | "pro" | "team" | "enterprise"
  default_supabase_region: string
  storage_buckets: StorageBucketConfig[]
  vercel_framework: string
  vercel_build_command: string | null
  vercel_output_directory: string | null
  env_vars_template: EnvVarTemplate[]
  schema_snapshot: SchemaSnapshot | null
  is_active: boolean
  version: number
  created_at: string
  updated_at: string
}

export interface ProjectTemplateWithApp extends ProjectTemplate {
  app: App
}

export type ProvisioningStepStatus = "pending" | "in_progress" | "completed" | "failed" | "skipped"
export type ProvisioningJobStatus = "pending" | "running" | "completed" | "failed" | "cancelled"

export interface ProvisioningStep {
  id: string
  label: string
  status: ProvisioningStepStatus
  started_at?: string
  completed_at?: string
  error?: string
  result?: Record<string, unknown>
  logs?: Array<{ timestamp: string; level: "info" | "error" | "success" | "warn"; message: string }>
}

export interface ProvisioningJob {
  id: string
  client_name: string
  client_slug: string
  app_id: string
  template_id: string
  supabase_plan: "free" | "pro" | "team" | "enterprise"
  supabase_region: string
  monthly_revenue: number
  status: ProvisioningJobStatus
  supabase_project_ref: string | null
  supabase_url: string | null
  github_repo_url: string | null
  vercel_project_url: string | null
  client_id: string | null
  steps: ProvisioningStep[]
  error_message: string | null
  error_step: string | null
  created_by: string
  started_at: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export interface ProvisioningJobWithDetails extends ProvisioningJob {
  app: App
  template: ProjectTemplate
}
