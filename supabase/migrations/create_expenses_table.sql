-- Migration: Créer la table expenses pour gérer les dépenses par client
-- Date: 2026-03-15

CREATE TABLE IF NOT EXISTS public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  description text NOT NULL,
  amount numeric(10, 2) NOT NULL CHECK (amount > 0),
  category text,
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  is_recurring boolean NOT NULL DEFAULT false,
  recurring_frequency text CHECK (recurring_frequency IN ('monthly', 'yearly')),
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT expenses_recurring_check CHECK (
    (is_recurring = false AND recurring_frequency IS NULL) OR
    (is_recurring = true AND recurring_frequency IS NOT NULL)
  )
);

-- Index pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_expenses_client_id ON public.expenses(client_id);
CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON public.expenses(expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses(category) WHERE category IS NOT NULL;

-- Trigger pour mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_expenses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_expenses_updated_at_trigger
  BEFORE UPDATE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION update_expenses_updated_at();

-- RLS Policies
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- Policy: Les utilisateurs authentifiés peuvent voir les dépenses de tous les clients
CREATE POLICY "Enable read access for authenticated users"
  ON public.expenses
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Seuls les admins peuvent créer des dépenses
CREATE POLICY "Enable insert for admin users only"
  ON public.expenses
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Policy: Seuls les admins peuvent modifier les dépenses
CREATE POLICY "Enable update for admin users only"
  ON public.expenses
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Policy: Seuls les admins peuvent supprimer les dépenses
CREATE POLICY "Enable delete for admin users only"
  ON public.expenses
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Commentaires pour la documentation
COMMENT ON TABLE public.expenses IS 'Table pour gérer les dépenses associées à chaque client';
COMMENT ON COLUMN public.expenses.client_id IS 'Référence au client propriétaire de la dépense';
COMMENT ON COLUMN public.expenses.description IS 'Description de la dépense';
COMMENT ON COLUMN public.expenses.amount IS 'Montant de la dépense en CAD';
COMMENT ON COLUMN public.expenses.category IS 'Catégorie de la dépense (ex: Marketing, Infrastructure)';
COMMENT ON COLUMN public.expenses.expense_date IS 'Date de la dépense';
COMMENT ON COLUMN public.expenses.is_recurring IS 'Indique si la dépense est récurrente';
COMMENT ON COLUMN public.expenses.recurring_frequency IS 'Fréquence de récurrence (monthly ou yearly)';
COMMENT ON COLUMN public.expenses.notes IS 'Notes additionnelles sur la dépense';
