# Commandes Git pour se connecter à GitHub

## 1. Configurer votre identité Git

```bash
# Configurer votre nom (remplacez par votre vrai nom)
git config user.name "Votre Nom"

# Configurer votre email (remplacez par votre email GitHub)
git config user.email "votre.email@example.com"
```

**Exemple :**
```bash
git config user.name "Jean Dupont"
git config user.email "jean.dupont@example.com"
```

## 2. Créer un Personal Access Token sur GitHub

1. Allez sur : https://github.com/settings/tokens
2. Cliquez sur "Generate new token" → "Generate new token (classic)"
3. Donnez un nom (ex: "Groupe 405 Panel")
4. Cochez la permission : **`repo`**
5. Cliquez sur "Generate token"
6. **COPIEZ LE TOKEN** (il commence par `ghp_...`)

## 3. Se connecter à GitHub avec le token

### Option A : Dans l'URL du remote (recommandé)

```bash
# Ajouter le remote avec votre token (remplacez USERNAME et TOKEN)
git remote add origin https://TOKEN@github.com/USERNAME/groupe-405-panel.git
```

**Exemple :**
```bash
git remote add origin https://ghp_abc123xyz@github.com/mon-username/groupe-405-panel.git
```

### Option B : Avec nom d'utilisateur et token

```bash
git remote add origin https://USERNAME:TOKEN@github.com/USERNAME/groupe-405-panel.git
```

## 4. Vérifier la configuration

```bash
# Voir votre configuration Git
git config user.name
git config user.email

# Voir les remotes configurés
git remote -v
```

## 5. Faire le premier commit et push

```bash
# Ajouter tous les fichiers
git add .

# Faire le commit
git commit -m "Initial commit: Groupe 405 Panel"

# Pousser vers GitHub
git push -u origin main
```

Si la branche s'appelle `master` au lieu de `main` :
```bash
git push -u origin master
```

## Commandes complètes (copier-coller)

Remplacez les valeurs entre `<>` :

```bash
# 1. Configurer votre identité
git config user.name "<Votre Nom>"
git config user.email "<votre.email@example.com>"

# 2. Ajouter le remote (remplacez <USERNAME> et <TOKEN>)
git remote add origin https://<TOKEN>@github.com/<USERNAME>/groupe-405-panel.git

# 3. Faire le commit et push
git add .
git commit -m "Initial commit: Groupe 405 Panel"
git push -u origin main
```

## Exemple concret

Si votre nom d'utilisateur GitHub est `jdupont` et votre token est `ghp_abc123xyz456` :

```bash
git config user.name "Jean Dupont"
git config user.email "jean.dupont@gmail.com"
git remote add origin https://ghp_abc123xyz456@github.com/jdupont/groupe-405-panel.git
git add .
git commit -m "Initial commit: Groupe 405 Panel"
git push -u origin main
```

## Stocker le token de manière sécurisée (optionnel)

Pour ne pas avoir à retaper le token à chaque fois :

```bash
# Windows - Git Credential Manager
git config --global credential.helper manager-core
```

Ensuite, lors du premier `git push`, Windows vous demandera vos identifiants une fois et les stockera de manière sécurisée.

## Vérifier que ça fonctionne

```bash
# Tester la connexion
git ls-remote origin

# Si ça fonctionne, vous verrez la liste des branches
```
