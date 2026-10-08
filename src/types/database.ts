// Généré depuis Supabase local : npm run db:types

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {

  "public": {
          Tables: {
            "ai_reviews": {
                  Row: {
                    "checks": NonNullable<Json>,"cost_amount": number,"cost_currency": string,"error_code": string | null,"error_message": string | null,"finished_at": string | null,"id": string,"input_tokens": number,"model": string,"output_tokens": number,"prompt_version": string,"provider": string,"qualification": Database["public"]['Enums']["ai_qualification"] | null,"request_id": string,"response_draft": string | null,"started_at": string,"status": Database["public"]['Enums']["execution_status"],"summary": string | null,"workflow_run_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "checks"?: NonNullable<Json>,"cost_amount"?: number,"cost_currency"?: string,"error_code"?: string | null,"error_message"?: string | null,"finished_at"?: string | null,"id"?: string,"input_tokens"?: number,"model": string,"output_tokens"?: number,"prompt_version": string,"provider": string,"qualification"?: Database["public"]['Enums']["ai_qualification"] | null,"request_id": string,"response_draft"?: string | null,"started_at"?: string,"status"?: Database["public"]['Enums']["execution_status"],"summary"?: string | null,"workflow_run_id"?: string | null
                  }
                  Update: {
                    "checks"?: NonNullable<Json>,"cost_amount"?: number,"cost_currency"?: string,"error_code"?: string | null,"error_message"?: string | null,"finished_at"?: string | null,"id"?: string,"input_tokens"?: number,"model"?: string,"output_tokens"?: number,"prompt_version"?: string,"provider"?: string,"qualification"?: Database["public"]['Enums']["ai_qualification"] | null,"request_id"?: string,"response_draft"?: string | null,"started_at"?: string,"status"?: Database["public"]['Enums']["execution_status"],"summary"?: string | null,"workflow_run_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "ai_reviews_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ai_reviews_workflow_run_id_fkey"
      columns: ["workflow_run_id"]
isOneToOne: false
      referencedRelation: "workflow_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"approval_rules": {
                  Row: {
                    "active": boolean,"created_at": string,"decision_hours": number | null,"director_amount_above": number | null,"director_days_above": number | null,"id": string,"name": string,"reminder_hours": number | null,"request_type": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"decision_hours"?: number | null,"director_amount_above"?: number | null,"director_days_above"?: number | null,"id"?: string,"name": string,"reminder_hours"?: number | null,"request_type": string,"version": number
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"decision_hours"?: number | null,"director_amount_above"?: number | null,"director_days_above"?: number | null,"id"?: string,"name"?: string,"reminder_hours"?: number | null,"request_type"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "approval_rules_request_type_fkey"
      columns: ["request_type"]
isOneToOne: false
      referencedRelation: "request_types"
      referencedColumns: ["code"]
    }
                  ]
                },"approval_steps": {
                  Row: {
                    "activated_at": string | null,"assignee_id": string,"created_at": string,"decided_at": string | null,"decided_by": string | null,"decision_comment": string | null,"due_at": string | null,"id": string,"position": number,"request_id": string,"required_role": Database["public"]['Enums']["app_role"],"status": Database["public"]['Enums']["approval_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "activated_at"?: string | null,"assignee_id": string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_comment"?: string | null,"due_at"?: string | null,"id"?: string,"position": number,"request_id": string,"required_role": Database["public"]['Enums']["app_role"],"status"?: Database["public"]['Enums']["approval_status"]
                  }
                  Update: {
                    "activated_at"?: string | null,"assignee_id"?: string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_comment"?: string | null,"due_at"?: string | null,"id"?: string,"position"?: number,"request_id"?: string,"required_role"?: Database["public"]['Enums']["app_role"],"status"?: Database["public"]['Enums']["approval_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "approval_steps_assignee_id_fkey"
      columns: ["assignee_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "approval_steps_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "approval_steps_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    }
                  ]
                },"leave_balance_history": {
                  Row: {
                    "actor_id": string | null,"balance_id": string,"id": number,"new_values": NonNullable<Json>,"old_values": Json | null,"recorded_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_id"?: string | null,"balance_id": string,"id"?: never,"new_values": NonNullable<Json>,"old_values"?: Json | null,"recorded_at"?: string
                  }
                  Update: {
                    "actor_id"?: string | null,"balance_id"?: string,"id"?: never,"new_values"?: NonNullable<Json>,"old_values"?: Json | null,"recorded_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "leave_balance_history_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "leave_balance_history_balance_id_fkey"
      columns: ["balance_id"]
isOneToOne: false
      referencedRelation: "leave_balances"
      referencedColumns: ["id"]
    }
                  ]
                },"leave_balances": {
                  Row: {
                    "allocated_days": number,"available_days": number | null,"consumed_days": number,"employee_id": string,"id": string,"reserved_days": number,"updated_at": string,"year": number
                  }
                  ComputedFields: never
                  Insert: {
                    "allocated_days"?: number,"available_days"?: never,"consumed_days"?: number,"employee_id": string,"id"?: string,"reserved_days"?: number,"updated_at"?: string,"year": number
                  }
                  Update: {
                    "allocated_days"?: number,"available_days"?: never,"consumed_days"?: number,"employee_id"?: string,"id"?: string,"reserved_days"?: number,"updated_at"?: string,"year"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "leave_balances_employee_id_fkey"
      columns: ["employee_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"notifications": {
                  Row: {
                    "approval_step_id": string | null,"attempts": number,"channel": Database["public"]['Enums']["notification_channel"],"created_at": string,"deduplication_key": string,"event_id": number | null,"id": string,"kind": string,"last_error": string | null,"next_attempt_at": string,"provider_message_id": string | null,"recipient_id": string,"request_id": string,"sent_at": string | null,"status": Database["public"]['Enums']["delivery_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "approval_step_id"?: string | null,"attempts"?: number,"channel"?: Database["public"]['Enums']["notification_channel"],"created_at"?: string,"deduplication_key": string,"event_id"?: number | null,"id"?: string,"kind": string,"last_error"?: string | null,"next_attempt_at"?: string,"provider_message_id"?: string | null,"recipient_id": string,"request_id": string,"sent_at"?: string | null,"status"?: Database["public"]['Enums']["delivery_status"]
                  }
                  Update: {
                    "approval_step_id"?: string | null,"attempts"?: number,"channel"?: Database["public"]['Enums']["notification_channel"],"created_at"?: string,"deduplication_key"?: string,"event_id"?: number | null,"id"?: string,"kind"?: string,"last_error"?: string | null,"next_attempt_at"?: string,"provider_message_id"?: string | null,"recipient_id"?: string,"request_id"?: string,"sent_at"?: string | null,"status"?: Database["public"]['Enums']["delivery_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "notifications_approval_step_id_fkey"
      columns: ["approval_step_id"]
isOneToOne: false
      referencedRelation: "approval_steps"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "notifications_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "request_events"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "notifications_recipient_id_fkey"
      columns: ["recipient_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "notifications_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    }
                  ]
                },"process_measurements": {
                  Row: {
                    "average_processing_hours": number,"cost_per_request_eur": number | null,"id": string,"measurement_method": string,"period_end": string,"period_start": string,"phase": string,"recorded_at": string,"sample_size": number
                  }
                  ComputedFields: never
                  Insert: {
                    "average_processing_hours": number,"cost_per_request_eur"?: number | null,"id"?: string,"measurement_method": string,"period_end": string,"period_start": string,"phase": string,"recorded_at"?: string,"sample_size": number
                  }
                  Update: {
                    "average_processing_hours"?: number,"cost_per_request_eur"?: number | null,"id"?: string,"measurement_method"?: string,"period_end"?: string,"period_start"?: string,"phase"?: string,"recorded_at"?: string,"sample_size"?: number
                  }
                  Relationships: [

                  ]
                },"profiles": {
                  Row: {
                    "created_at": string,"first_name": string,"id": string,"last_name": string,"manager_id": string | null,"role": Database["public"]['Enums']["app_role"]
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"first_name"?: string,"id": string,"last_name"?: string,"manager_id"?: string | null,"role"?: Database["public"]['Enums']["app_role"]
                  }
                  Update: {
                    "created_at"?: string,"first_name"?: string,"id"?: string,"last_name"?: string,"manager_id"?: string | null,"role"?: Database["public"]['Enums']["app_role"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "profiles_manager_id_fkey"
      columns: ["manager_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"request_attachments": {
                  Row: {
                    "created_at": string,"filename": string,"id": string,"mime_type": string,"request_id": string,"size_bytes": number,"storage_path": string,"uploaded_by": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"filename": string,"id"?: string,"mime_type": string,"request_id": string,"size_bytes": number,"storage_path": string,"uploaded_by"?: string
                  }
                  Update: {
                    "created_at"?: string,"filename"?: string,"id"?: string,"mime_type"?: string,"request_id"?: string,"size_bytes"?: number,"storage_path"?: string,"uploaded_by"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "request_attachments_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "request_attachments_uploaded_by_fkey"
      columns: ["uploaded_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"request_events": {
                  Row: {
                    "actor_id": string | null,"approval_step_id": string | null,"comment": string | null,"event_type": string,"id": number,"new_status": Database["public"]['Enums']["request_status"] | null,"occurred_at": string,"old_status": Database["public"]['Enums']["request_status"] | null,"request_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_id"?: string | null,"approval_step_id"?: string | null,"comment"?: string | null,"event_type": string,"id"?: never,"new_status"?: Database["public"]['Enums']["request_status"] | null,"occurred_at"?: string,"old_status"?: Database["public"]['Enums']["request_status"] | null,"request_id": string
                  }
                  Update: {
                    "actor_id"?: string | null,"approval_step_id"?: string | null,"comment"?: string | null,"event_type"?: string,"id"?: never,"new_status"?: Database["public"]['Enums']["request_status"] | null,"occurred_at"?: string,"old_status"?: Database["public"]['Enums']["request_status"] | null,"request_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "request_events_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "request_events_approval_step_id_fkey"
      columns: ["approval_step_id"]
isOneToOne: false
      referencedRelation: "approval_steps"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "request_events_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    }
                  ]
                },"request_types": {
                  Row: {
                    "active": boolean,"code": string,"label": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"code": string,"label": string
                  }
                  Update: {
                    "active"?: boolean,"code"?: string,"label"?: string
                  }
                  Relationships: [

                  ]
                },"requests": {
                  Row: {
                    "amount": number | null,"approval_rule_id": string | null,"completed_at": string | null,"created_at": string,"currency": string,"description": string,"end_date": string | null,"id": string,"manager_id": string | null,"quantity": number | null,"reference": number,"request_type": string,"requested_days": number | null,"requester_id": string,"start_date": string | null,"status": Database["public"]['Enums']["request_status"],"submitted_at": string | null,"title": string,"training_provider": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount"?: number | null,"approval_rule_id"?: string | null,"completed_at"?: string | null,"created_at"?: string,"currency"?: string,"description"?: string,"end_date"?: string | null,"id"?: string,"manager_id"?: string | null,"quantity"?: number | null,"reference"?: never,"request_type": string,"requested_days"?: number | null,"requester_id"?: string,"start_date"?: string | null,"status"?: Database["public"]['Enums']["request_status"],"submitted_at"?: string | null,"title": string,"training_provider"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "amount"?: number | null,"approval_rule_id"?: string | null,"completed_at"?: string | null,"created_at"?: string,"currency"?: string,"description"?: string,"end_date"?: string | null,"id"?: string,"manager_id"?: string | null,"quantity"?: number | null,"reference"?: never,"request_type"?: string,"requested_days"?: number | null,"requester_id"?: string,"start_date"?: string | null,"status"?: Database["public"]['Enums']["request_status"],"submitted_at"?: string | null,"title"?: string,"training_provider"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "requests_approval_rule_id_fkey"
      columns: ["approval_rule_id"]
isOneToOne: false
      referencedRelation: "approval_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "requests_manager_id_fkey"
      columns: ["manager_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "requests_request_type_fkey"
      columns: ["request_type"]
isOneToOne: false
      referencedRelation: "request_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "requests_requester_id_fkey"
      columns: ["requester_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"workflow_runs": {
                  Row: {
                    "attempt": number,"error_code": string | null,"error_message": string | null,"execution_id": string,"finished_at": string | null,"id": string,"request_id": string,"started_at": string,"status": Database["public"]['Enums']["execution_status"],"workflow_key": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempt"?: number,"error_code"?: string | null,"error_message"?: string | null,"execution_id": string,"finished_at"?: string | null,"id"?: string,"request_id": string,"started_at"?: string,"status"?: Database["public"]['Enums']["execution_status"],"workflow_key": string
                  }
                  Update: {
                    "attempt"?: number,"error_code"?: string | null,"error_message"?: string | null,"execution_id"?: string,"finished_at"?: string | null,"id"?: string,"request_id"?: string,"started_at"?: string,"status"?: Database["public"]['Enums']["execution_status"],"workflow_key"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "workflow_runs_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "requests"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "cancel_hr_request":
{ Args: { "p_request_id": string }; Returns: {
              "amount": number | null,
"approval_rule_id": string | null,
"completed_at": string | null,
"created_at": string,
"currency": string,
"description": string,
"end_date": string | null,
"id": string,
"manager_id": string | null,
"quantity": number | null,
"reference": number,
"request_type": string,
"requested_days": number | null,
"requester_id": string,
"start_date": string | null,
"status": Database["public"]['Enums']["request_status"],
"submitted_at": string | null,
"title": string,
"training_provider": string | null,
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "requests"
        isOneToOne: true
        isSetofReturn: false
      } },
"decide_hr_approval":
{ Args: { "p_approve": boolean,"p_comment"?: string,"p_step_id": string }; Returns: {
              "activated_at": string | null,
"assignee_id": string,
"created_at": string,
"decided_at": string | null,
"decided_by": string | null,
"decision_comment": string | null,
"due_at": string | null,
"id": string,
"position": number,
"request_id": string,
"required_role": Database["public"]['Enums']["app_role"],
"status": Database["public"]['Enums']["approval_status"]
            }
                          SetofOptions: {
        from: "*"
        to: "approval_steps"
        isOneToOne: true
        isSetofReturn: false
      } },
"submit_hr_request":
{ Args: { "p_request_id": string }; Returns: {
              "amount": number | null,
"approval_rule_id": string | null,
"completed_at": string | null,
"created_at": string,
"currency": string,
"description": string,
"end_date": string | null,
"id": string,
"manager_id": string | null,
"quantity": number | null,
"reference": number,
"request_type": string,
"requested_days": number | null,
"requester_id": string,
"start_date": string | null,
"status": Database["public"]['Enums']["request_status"],
"submitted_at": string | null,
"title": string,
"training_provider": string | null,
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "requests"
        isOneToOne: true
        isSetofReturn: false
      } },
"transition_hr_request":
{ Args: { "p_request_id": string,"p_status": Database["public"]['Enums']["request_status"] }; Returns: {
              "amount": number | null,
"approval_rule_id": string | null,
"completed_at": string | null,
"created_at": string,
"currency": string,
"description": string,
"end_date": string | null,
"id": string,
"manager_id": string | null,
"quantity": number | null,
"reference": number,
"request_type": string,
"requested_days": number | null,
"requester_id": string,
"start_date": string | null,
"status": Database["public"]['Enums']["request_status"],
"submitted_at": string | null,
"title": string,
"training_provider": string | null,
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "requests"
        isOneToOne: true
        isSetofReturn: false
      } }
          }
          Enums: {
            "ai_qualification": "eligible"|"needs_review"|"invalid","app_role": "employee"|"manager"|"hr"|"director","approval_status": "waiting"|"pending"|"approved"|"rejected"|"skipped","delivery_status": "queued"|"sending"|"sent"|"failed","execution_status": "running"|"succeeded"|"failed","notification_channel": "email"|"slack","request_status": "draft"|"submitted"|"under_review"|"pending_approval"|"approved"|"rejected"|"cancelled"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "ai_qualification": ["eligible", "needs_review", "invalid"],"app_role": ["employee", "manager", "hr", "director"],"approval_status": ["waiting", "pending", "approved", "rejected", "skipped"],"delivery_status": ["queued", "sending", "sent", "failed"],"execution_status": ["running", "succeeded", "failed"],"notification_channel": ["email", "slack"],"request_status": ["draft", "submitted", "under_review", "pending_approval", "approved", "rejected", "cancelled"]
          }
        }
} as const
