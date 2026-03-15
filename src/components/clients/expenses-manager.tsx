"use client"

import { useState, useTransition } from "react"
import {
  createExpense,
  updateExpense,
  deleteExpense,
} from "@/app/(dashboard)/clients/[slug]/actions"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Loader2, Plus, Edit2, Trash2 } from "lucide-react"
import { formatCurrency } from "@/lib/utils"
import { toast } from "sonner"
import type { Expense } from "@/types"

interface ExpensesManagerProps {
  clientId: string
  expenses: Expense[]
  isAdmin: boolean
}

export function ExpensesManager({ clientId, expenses, isAdmin }: ExpensesManagerProps) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [editingExpense, setEditingExpense] = useState<Expense | null>(null)
  const [isPending, startTransition] = useTransition()

  const [formData, setFormData] = useState({
    description: "",
    amount: "",
    category: "",
    expenseDate: new Date().toISOString().split("T")[0],
    isRecurring: false,
    recurringFrequency: "" as "monthly" | "yearly" | "",
    notes: "",
  })

  function handleOpenDialog(expense?: Expense) {
    if (expense) {
      setEditingExpense(expense)
      setFormData({
        description: expense.description,
        amount: expense.amount.toString(),
        category: expense.category || "",
        expenseDate: expense.expense_date.split("T")[0],
        isRecurring: expense.is_recurring,
        recurringFrequency: expense.recurring_frequency || "",
        notes: expense.notes || "",
      })
    } else {
      setEditingExpense(null)
      setFormData({
        description: "",
        amount: "",
        category: "",
        expenseDate: new Date().toISOString().split("T")[0],
        isRecurring: false,
        recurringFrequency: "",
        notes: "",
      })
    }
    setIsDialogOpen(true)
  }

  function handleCloseDialog() {
    setIsDialogOpen(false)
    setEditingExpense(null)
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    const submitData = new FormData()
    submitData.set("clientId", clientId)
    submitData.set("description", formData.description)
    submitData.set("amount", formData.amount)
    submitData.set("category", formData.category || "")
    submitData.set("expenseDate", formData.expenseDate)
    submitData.set("isRecurring", formData.isRecurring.toString())
    submitData.set("recurringFrequency", formData.recurringFrequency || "")
    submitData.set("notes", formData.notes || "")

    startTransition(async () => {
      const result = editingExpense
        ? await updateExpense(submitData, editingExpense.id)
        : await createExpense(submitData)

      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success(editingExpense ? "Dépense mise à jour" : "Dépense ajoutée")
        handleCloseDialog()
        window.location.reload()
      }
    })
  }

  function handleDelete(expenseId: string) {
    if (!confirm("Êtes-vous sûr de vouloir supprimer cette dépense ?")) return

    const submitData = new FormData()
    submitData.set("expenseId", expenseId)
    submitData.set("clientId", clientId)

    startTransition(async () => {
      const result = await deleteExpense(submitData)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success("Dépense supprimée")
        window.location.reload()
      }
    })
  }

  const totalExpenses = expenses.reduce((sum, exp) => {
    if (exp.is_recurring && exp.recurring_frequency === "monthly") {
      return sum + exp.amount
    } else if (exp.is_recurring && exp.recurring_frequency === "yearly") {
      return sum + exp.amount / 12
    }
    // Pour les dépenses ponctuelles, on calcule le total annuel basé sur les dépenses de cette année
    const expenseYear = new Date(exp.expense_date).getFullYear()
    const currentYear = new Date().getFullYear()
    return expenseYear === currentYear ? sum + exp.amount : sum
  }, 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-sm font-medium">Dépenses</h3>
          <p className="text-xs text-muted-foreground mt-1">
            Total mensuel estimé: {formatCurrency(totalExpenses)}
          </p>
        </div>
        {isAdmin && (
          <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm" variant="outline" onClick={() => handleOpenDialog()}>
                <Plus className="h-4 w-4 mr-2" />
                Ajouter
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-2xl">
              <DialogHeader>
                <DialogTitle>
                  {editingExpense ? "Modifier la dépense" : "Ajouter une dépense"}
                </DialogTitle>
                <DialogDescription>
                  {editingExpense
                    ? "Modifiez les informations de la dépense"
                    : "Ajoutez une nouvelle dépense associée à ce client"}
                </DialogDescription>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="description">Description *</Label>
                    <Input
                      id="description"
                      value={formData.description}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, description: e.target.value }))
                      }
                      required
                      disabled={isPending}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="amount">Montant ($ CAD) *</Label>
                    <Input
                      id="amount"
                      type="number"
                      step="0.01"
                      min="0.01"
                      value={formData.amount}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, amount: e.target.value }))
                      }
                      required
                      disabled={isPending}
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="category">Catégorie</Label>
                    <Input
                      id="category"
                      value={formData.category}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, category: e.target.value }))
                      }
                      placeholder="Ex: Marketing, Infrastructure..."
                      disabled={isPending}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="expenseDate">Date *</Label>
                    <Input
                      id="expenseDate"
                      type="date"
                      value={formData.expenseDate}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, expenseDate: e.target.value }))
                      }
                      required
                      disabled={isPending}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="isRecurring"
                      checked={formData.isRecurring}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, isRecurring: e.target.checked }))
                      }
                      disabled={isPending}
                      className="rounded"
                    />
                    <Label htmlFor="isRecurring">Dépense récurrente</Label>
                  </div>
                  {formData.isRecurring && (
                    <Select
                      value={formData.recurringFrequency}
                      onValueChange={(value: "monthly" | "yearly") =>
                        setFormData((prev) => ({ ...prev, recurringFrequency: value }))
                      }
                      disabled={isPending}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Fréquence" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="monthly">Mensuelle</SelectItem>
                        <SelectItem value="yearly">Annuelle</SelectItem>
                      </SelectContent>
                    </Select>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="notes">Notes</Label>
                  <Textarea
                    id="notes"
                    value={formData.notes}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, notes: e.target.value }))
                    }
                    rows={3}
                    disabled={isPending}
                  />
                </div>

                <DialogFooter>
                  <Button type="button" variant="outline" onClick={handleCloseDialog} disabled={isPending}>
                    Annuler
                  </Button>
                  <Button type="submit" disabled={isPending}>
                    {isPending ? (
                      <Loader2 className="h-4 w-4 animate-spin mr-2" />
                    ) : null}
                    {editingExpense ? "Modifier" : "Ajouter"}
                  </Button>
                </DialogFooter>
              </form>
            </DialogContent>
          </Dialog>
        )}
      </div>

      {expenses.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-8">
          Aucune dépense enregistrée
        </p>
      ) : (
        <div className="rounded-md border border-border/50">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Description</TableHead>
                <TableHead>Catégorie</TableHead>
                <TableHead className="text-right">Montant</TableHead>
                <TableHead>Date</TableHead>
                <TableHead>Type</TableHead>
                {isAdmin && <TableHead className="text-right">Actions</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {expenses
                .sort((a, b) => new Date(b.expense_date).getTime() - new Date(a.expense_date).getTime())
                .map((expense) => (
                  <TableRow key={expense.id}>
                    <TableCell className="font-medium">{expense.description}</TableCell>
                    <TableCell>
                      {expense.category ? (
                        <Badge variant="outline">{expense.category}</Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-medium">
                      {formatCurrency(expense.amount)}
                    </TableCell>
                    <TableCell>
                      {new Date(expense.expense_date).toLocaleDateString("fr-CA")}
                    </TableCell>
                    <TableCell>
                      {expense.is_recurring ? (
                        <Badge variant="secondary">
                          {expense.recurring_frequency === "monthly" ? "Mensuelle" : "Annuelle"}
                        </Badge>
                      ) : (
                        <Badge variant="outline">Ponctuelle</Badge>
                      )}
                    </TableCell>
                    {isAdmin && (
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-2">
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => handleOpenDialog(expense)}
                            disabled={isPending}
                          >
                            <Edit2 className="h-4 w-4" />
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => handleDelete(expense.id)}
                            disabled={isPending}
                          >
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </div>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  )
}
